"""Single-port runtime combining List Config, Cycle Timer, and List Execute.

The runtime is an executable event-level contract. Management writes are
applied at the current PTP sample after events already due at that sample,
matching registered/nonblocking update semantics. At a shared timestamp the
internal event priority is:

1. Admin-to-Oper configuration activation;
2. CycleStart (which preempts an expiring list entry);
3. Gate Control List interval expiry.

The priority is explicit so callers and tests do not depend on Python call
ordering or on the ordering of independent IEEE state-machine processes.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from .configuration import (
    ConfigurationActivation,
    ConfigurationController,
    ScheduleConfiguration,
)
from .execution import ListExecutor, ScheduleValidationError, ValidatedSchedule
from .time import PtpTime, Timebase, TimeConfigurationError

UINT8_MAX = (1 << 8) - 1


class RuntimeEventKind(StrEnum):
    CONFIGURATION_ACTIVATED = "configuration_activated"
    CYCLE_STARTED = "cycle_started"
    LIST_ENTRY_STARTED = "list_entry_started"
    GATE_STATES_CHANGED = "gate_states_changed"
    LIST_COMPLETED = "list_completed"
    GATES_INITIALIZED = "gates_initialized"


@dataclass(frozen=True, slots=True)
class RuntimeEvent:
    """Observable state transition emitted by :class:`GateControlRuntime`.

    ``time`` is the PTP sample at which the runtime applied the event.
    ``scheduled_time`` preserves the nominal time selected by the Qbv timing
    rules; it differs only when a runtime is deliberately advanced past a due
    event rather than being stepped at every implementation tick.
    """

    time: PtpTime
    kind: RuntimeEventKind
    scheduled_time: PtpTime | None = None
    gate_states: int | None = None
    list_pointer: int | None = None
    activation: ConfigurationActivation | None = None


class RuntimeStateError(RuntimeError):
    """The event-level runtime cannot maintain a consistent timer state."""


class GateControlRuntime:
    """Coordinate the three per-port Qbv state-machine responsibilities.

    ``advance_to`` may skip over many implementation ticks. The runtime still
    processes every GCL interval, cycle start, and configuration deadline in
    chronological order. No per-tick Python loop is required.

    A cycle boundary has priority over a GCL interval expiry at the same PTP
    timestamp: the new cycle resets ListPointer and executes entry zero,
    preempting the entry that would otherwise expire at that timestamp.
    """

    def __init__(
        self,
        *,
        timebase: Timebase,
        admin_config: ScheduleConfiguration,
        current_time: PtpTime,
        admin_gate_states: int = UINT8_MAX,
        oper_config: ScheduleConfiguration | None = None,
        gate_enabled: bool = False,
    ) -> None:
        if not isinstance(current_time, PtpTime):
            raise TypeError("current_time must be a PtpTime")
        self._validate_gate_states(admin_gate_states)
        self._timebase = timebase
        self._current_time = current_time
        self._admin_gate_states = admin_gate_states
        self._controller = ConfigurationController(
            timebase=timebase,
            admin_config=admin_config,
            oper_config=oper_config,
            gate_enabled=gate_enabled,
        )
        self._executor = ListExecutor(timebase=timebase)
        self._executor.initialize(admin_gate_states)
        self._active_schedule: ValidatedSchedule | None = None
        self._next_cycle_start: PtpTime | None = None
        self._list_deadline: PtpTime | None = None
        self._list_last_update: PtpTime | None = None

        if gate_enabled:
            self._next_cycle_start = self._controller.next_cycle_start_time(current_time)
        self._initial_events = tuple(self._process_timestamp(current_time))

    @property
    def current_time(self) -> PtpTime:
        return self._current_time

    @property
    def gate_enabled(self) -> bool:
        return self._controller.gate_enabled

    @property
    def admin_config(self) -> ScheduleConfiguration:
        return self._controller.admin_config

    @property
    def oper_config(self) -> ScheduleConfiguration | None:
        return self._controller.oper_config

    @property
    def config_change(self) -> bool:
        return self._controller.config_change

    @property
    def config_pending(self) -> bool:
        return self._controller.config_pending

    @property
    def config_change_time(self) -> PtpTime | None:
        return self._controller.config_change_time

    @property
    def config_change_error(self) -> int:
        return self._controller.config_change_error

    @property
    def admin_gate_states(self) -> int:
        return self._admin_gate_states

    @property
    def gate_states(self) -> int:
        return self._executor.gate_states

    @property
    def list_pointer(self) -> int:
        return self._executor.list_pointer

    @property
    def remaining_ticks(self) -> int | None:
        if self._list_deadline is None:
            return None
        remaining_ns = (
            self._list_deadline.total_nanoseconds
            - self._current_time.total_nanoseconds
        )
        if remaining_ns <= 0:
            return 0
        ticks, remainder = divmod(remaining_ns, self._timebase.tick_granularity_ns)
        if remainder:
            raise RuntimeStateError("remaining GCL interval is not tick aligned")
        return ticks

    @property
    def next_cycle_start_time(self) -> PtpTime | None:
        return self._next_cycle_start

    @property
    def list_deadline(self) -> PtpTime | None:
        return self._list_deadline

    @property
    def initial_events(self) -> tuple[RuntimeEvent, ...]:
        """Transitions caused by the initial state and timestamp, if any."""
        return self._initial_events

    def set_admin_config(self, config: ScheduleConfiguration) -> None:
        """Replace Admin when the List Config machine is not pending."""
        self._controller.set_admin_config(config)

    def set_admin_gate_states(self, gate_states: int) -> tuple[RuntimeEvent, ...]:
        """Update the independent AdminGateStates variable.

        The operative gate output changes when List Execute enters INIT (for
        example on a GateEnabled falling transition), not merely because the
        administrative register was written.
        """
        self._validate_gate_states(gate_states)
        self._admin_gate_states = gate_states
        if not self._controller.gate_enabled:
            self._executor.initialize(gate_states)
            return (
                RuntimeEvent(
                    time=self._current_time,
                    kind=RuntimeEventKind.GATES_INITIALIZED,
                    gate_states=self._executor.gate_states,
                ),
            )
        return ()

    def request_config_change(self) -> tuple[RuntimeEvent, ...]:
        """Request a configuration change at the current PTP sample."""
        events = list(self.advance_to(self._current_time))
        self._controller.request_config_change(self._current_time)

        # Process a ConfigChangeTime equal to this sample before asking Cycle
        # Timer for a future boundary. Exact-equality activation must not be
        # converted into a late activation by a speculative next-tick query.
        events.extend(self._process_timestamp(self._current_time))
        if self._controller.config_pending:
            # A future pending change can move the next CycleStart to
            # ConfigChangeTime (or preserve an earlier old-cycle boundary).
            self._reschedule_cycle_after_current_time()
        return tuple(events)

    def set_gate_enabled(self, enabled: bool) -> tuple[RuntimeEvent, ...]:
        """Apply GateEnabled at the current PTP sample.

        Events already due at this sample are processed first. The management
        write then changes the registered control state, after which the new
        state is evaluated at the same sample.
        """
        if type(enabled) is not bool:
            raise TypeError("enabled must be bool")
        events = list(self.advance_to(self._current_time))
        if enabled == self._controller.gate_enabled:
            return tuple(events)

        self._controller.set_gate_enabled(enabled, self._current_time)
        self._next_cycle_start = None
        self._list_deadline = None
        self._list_last_update = None
        self._active_schedule = None

        if not enabled:
            self._executor.initialize(self._admin_gate_states)
            events.append(
                RuntimeEvent(
                    time=self._current_time,
                    kind=RuntimeEventKind.GATES_INITIALIZED,
                    gate_states=self._executor.gate_states,
                )
            )
        else:
            self._next_cycle_start = self._controller.next_cycle_start_time(
                self._current_time
            )
            events.extend(self._process_timestamp(self._current_time))
            if self._next_cycle_start is None and self._controller.oper_config is not None:
                self._reschedule_cycle_after_current_time()

        return tuple(events)

    def advance_to(self, target_time: PtpTime) -> tuple[RuntimeEvent, ...]:
        """Advance time while processing every internal event up to target."""
        if not isinstance(target_time, PtpTime):
            raise TypeError("target_time must be a PtpTime")
        if target_time < self._current_time:
            raise TimeConfigurationError("CurrentTime must not move backwards")
        self._timebase.require_aligned(target_time, self._current_time)

        events: list[RuntimeEvent] = []
        events.extend(self._process_timestamp(self._current_time))

        while self._current_time < target_time:
            deadline = self._next_deadline()
            if deadline is None or deadline > target_time:
                self._current_time = target_time
                # Keep the controller's time monotonic even when no internal
                # event occurs before the caller's requested target.
                self._controller.advance_time(target_time)
                break
            if deadline < self._current_time:
                raise RuntimeStateError("an internal deadline is earlier than CurrentTime")
            if deadline == self._current_time:
                # _process_timestamp() must consume every event due now. A
                # retained zero-distance deadline would otherwise spin.
                before = self._deadline_state()
                events.extend(self._process_timestamp(self._current_time))
                if self._deadline_state() == before:
                    raise RuntimeStateError("an internal event deadline made no progress")
                continue

            self._current_time = deadline
            events.extend(self._process_timestamp(deadline))

        return tuple(events)

    def _process_timestamp(self, timestamp: PtpTime) -> list[RuntimeEvent]:
        events: list[RuntimeEvent] = []
        activation = self._controller.advance_time(timestamp)
        activation_cycle_start: PtpTime | None = None
        if activation is not None:
            events.append(
                RuntimeEvent(
                    time=timestamp,
                    kind=RuntimeEventKind.CONFIGURATION_ACTIVATED,
                    scheduled_time=activation.config_change_time,
                    activation=activation,
                )
            )
            activation_cycle_start = activation.cycle_start_time
            self._next_cycle_start = activation_cycle_start

        due_cycle_start: PtpTime | None = None
        if self._controller.gate_enabled:
            if activation_cycle_start is not None and activation_cycle_start <= timestamp:
                due_cycle_start = activation_cycle_start
            elif self._next_cycle_start is not None and self._next_cycle_start <= timestamp:
                due_cycle_start = self._next_cycle_start

        if due_cycle_start is not None:
            oper = self._controller.oper_config
            if oper is None:
                raise RuntimeStateError("CycleStart occurred without an operational schedule")
            self._start_cycle(
                schedule=oper.schedule,
                scheduled_start=due_cycle_start,
                applied_time=timestamp,
                events=events,
            )
            self._schedule_next_cycle_after(timestamp)
            return events

        if self._controller.gate_enabled and self._list_deadline is not None:
            if self._list_deadline <= timestamp:
                self._expire_list_interval(timestamp, events)

        # If an activation selected a future CycleStartTime, retain it. If no
        # cycle is active yet and an operational schedule exists, schedule the
        # next start from the current time sample.
        if (
            self._controller.gate_enabled
            and self._next_cycle_start is None
            and self._controller.oper_config is not None
        ):
            self._schedule_next_cycle_after(timestamp)

        return events

    def _start_cycle(
        self,
        *,
        schedule: ValidatedSchedule,
        scheduled_start: PtpTime,
        applied_time: PtpTime,
        events: list[RuntimeEvent],
    ) -> None:
        old_gate_states = self._executor.gate_states
        self._active_schedule = schedule
        self._executor.start_cycle(schedule)

        elapsed_ns = applied_time.total_nanoseconds - scheduled_start.total_nanoseconds
        tick_ns = self._timebase.tick_granularity_ns
        elapsed_ticks, remainder = divmod(elapsed_ns, tick_ns)
        if remainder:
            raise RuntimeStateError("late CycleStart is not aligned to the implementation timebase")
        if elapsed_ticks:
            # Recover the correct gate state if a caller advances the runtime
            # past a due CycleStart in one step. A cycle restarts periodically;
            # only the offset within the most recent cycle affects ListExecute.
            skipped_cycles, cycle_offset = divmod(elapsed_ticks, schedule.cycle_ticks)
            self._executor.advance_ticks(cycle_offset)
            effective_start_ns = (
                scheduled_start.total_nanoseconds + skipped_cycles * schedule.cycle_time_ns
            )
            effective_start = PtpTime.from_total_nanoseconds(effective_start_ns)
        else:
            effective_start = scheduled_start

        events.append(
            RuntimeEvent(
                time=applied_time,
                kind=RuntimeEventKind.CYCLE_STARTED,
                scheduled_time=effective_start,
                gate_states=self._executor.gate_states,
                list_pointer=self._executor.list_pointer,
            )
        )
        if schedule.entries:
            events.append(
                RuntimeEvent(
                    time=applied_time,
                    kind=RuntimeEventKind.LIST_ENTRY_STARTED,
                    scheduled_time=effective_start,
                    gate_states=self._executor.gate_states,
                    list_pointer=self._executor.list_pointer,
                )
            )
        if self._executor.gate_states != old_gate_states:
            events.append(
                RuntimeEvent(
                    time=applied_time,
                    kind=RuntimeEventKind.GATE_STATES_CHANGED,
                    scheduled_time=effective_start,
                    gate_states=self._executor.gate_states,
                    list_pointer=self._executor.list_pointer,
                )
            )

        self._list_last_update = applied_time
        self._refresh_list_deadline(applied_time)

    def _expire_list_interval(
        self,
        timestamp: PtpTime,
        events: list[RuntimeEvent],
    ) -> None:
        if self._list_last_update is None or self._executor.remaining_ticks is None:
            raise RuntimeStateError("list deadline exists without an active list interval")
        elapsed_ns = timestamp.total_nanoseconds - self._list_last_update.total_nanoseconds
        tick_ns = self._timebase.tick_granularity_ns
        elapsed_ticks, remainder = divmod(elapsed_ns, tick_ns)
        if remainder:
            raise RuntimeStateError("GCL interval expiry is not tick aligned")
        if elapsed_ticks <= 0:
            raise RuntimeStateError("GCL interval expiry did not advance time")

        old_pointer = self._executor.list_pointer
        old_gate_states = self._executor.gate_states
        self._executor.advance_ticks(elapsed_ticks)
        self._list_last_update = timestamp

        if self._executor.remaining_ticks is None:
            if self._active_schedule is None:
                raise RuntimeStateError("list completed without an active schedule")
            if self._executor.list_pointer != len(self._active_schedule.entries):
                raise RuntimeStateError("ListExecute stopped before the end of the GCL")
            events.append(
                RuntimeEvent(
                    time=timestamp,
                    kind=RuntimeEventKind.LIST_COMPLETED,
                    gate_states=self._executor.gate_states,
                    list_pointer=self._executor.list_pointer,
                )
            )
            self._list_deadline = None
            self._list_last_update = None
            return

        if self._executor.list_pointer == old_pointer:
            raise RuntimeStateError("GCL interval expired without advancing ListPointer")
        events.append(
            RuntimeEvent(
                time=timestamp,
                kind=RuntimeEventKind.LIST_ENTRY_STARTED,
                gate_states=self._executor.gate_states,
                list_pointer=self._executor.list_pointer,
            )
        )
        if self._executor.gate_states != old_gate_states:
            events.append(
                RuntimeEvent(
                    time=timestamp,
                    kind=RuntimeEventKind.GATE_STATES_CHANGED,
                    gate_states=self._executor.gate_states,
                    list_pointer=self._executor.list_pointer,
                )
            )
        self._refresh_list_deadline(timestamp)

    def _schedule_next_cycle_after(self, timestamp: PtpTime) -> None:
        if not self._controller.gate_enabled or self._controller.oper_config is None:
            self._next_cycle_start = None
            return
        probe_time = PtpTime.from_total_nanoseconds(
            timestamp.total_nanoseconds + self._timebase.tick_granularity_ns
        )
        try:
            self._next_cycle_start = self._controller.next_cycle_start_time(probe_time)
        except TimeConfigurationError as error:
            raise ScheduleValidationError(str(error)) from error
        if self._next_cycle_start is not None and self._next_cycle_start < timestamp:
            raise RuntimeStateError("Cycle Timer selected a cycle start in the past")

    def _reschedule_cycle_after_current_time(self) -> None:
        if not self._controller.gate_enabled or self._controller.oper_config is None:
            self._next_cycle_start = None
            return
        self._schedule_next_cycle_after(self._current_time)

    def _refresh_list_deadline(self, timestamp: PtpTime) -> None:
        remaining_ticks = self._executor.remaining_ticks
        if remaining_ticks is None:
            self._list_deadline = None
            return
        deadline_ns = (
            timestamp.total_nanoseconds
            + remaining_ticks * self._timebase.tick_granularity_ns
        )
        self._list_deadline = PtpTime.from_total_nanoseconds(deadline_ns)

    def _next_deadline(self) -> PtpTime | None:
        candidates: list[PtpTime] = []
        if self._controller.config_pending:
            change_time = self._controller.config_change_time
            if change_time is None:
                raise RuntimeStateError("ConfigPending has no ConfigChangeTime")
            candidates.append(change_time)
        if self._next_cycle_start is not None:
            candidates.append(self._next_cycle_start)
        if self._list_deadline is not None:
            candidates.append(self._list_deadline)
        return min(candidates) if candidates else None

    def _deadline_state(
        self,
    ) -> tuple[
        PtpTime | None,
        PtpTime | None,
        PtpTime | None,
        int,
        int | None,
    ]:
        return (
            self._controller.config_change_time if self._controller.config_pending else None,
            self._next_cycle_start,
            self._list_deadline,
            self._executor.list_pointer,
            self._executor.remaining_ticks,
        )

    @staticmethod
    def _validate_gate_states(gate_states: int) -> None:
        if type(gate_states) is not int or not 0 <= gate_states <= UINT8_MAX:
            raise ScheduleValidationError("AdminGateStates must fit uint8")
