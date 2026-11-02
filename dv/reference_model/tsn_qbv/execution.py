"""Behavioral model of the Qbv List Execute operation subset."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Iterable

from .time import CycleTime, Timebase, TimeConfigurationError


UINT8_MAX = (1 << 8) - 1
UINT32_MAX = (1 << 32) - 1


class ScheduleValidationError(ValueError):
    """An administrative gate-control list is not supported by this profile."""


class GateOperation(IntEnum):
    SET_GATE_STATES = 0


@dataclass(frozen=True, slots=True)
class GateControlEntry:
    operation: GateOperation
    gate_states: int
    time_interval_ns: int

    def __post_init__(self) -> None:
        if self.operation is not GateOperation.SET_GATE_STATES:
            raise ScheduleValidationError("unsupported GateControlEntry operation")
        if type(self.gate_states) is not int or not 0 <= self.gate_states <= UINT8_MAX:
            raise ScheduleValidationError("GateState must fit uint8")
        if (
            type(self.time_interval_ns) is not int
            or not 0 <= self.time_interval_ns <= UINT32_MAX
        ):
            raise ScheduleValidationError("TimeIntervalValue must fit uint32 nanoseconds")

    @property
    def effective_interval_ns(self) -> int:
        # IEEE 802.1Qbv SetGateStates assigns one nanosecond when the value is zero.
        return max(self.time_interval_ns, 1)


@dataclass(frozen=True, slots=True)
class ValidatedSchedule:
    """Immutable schedule prepared for one specific implementation timebase."""

    entries: tuple[GateControlEntry, ...]
    entry_interval_ticks: tuple[int, ...]
    cycle_time: CycleTime
    cycle_time_ns: int
    cycle_ticks: int
    total_interval_ns: int
    tick_granularity_x10_ns: int

    def __post_init__(self) -> None:
        if not isinstance(self.entries, tuple) or not isinstance(self.entry_interval_ticks, tuple):
            raise ScheduleValidationError("validated schedule storage must be immutable tuples")
        if len(self.entries) != len(self.entry_interval_ticks):
            raise ScheduleValidationError("validated entry and interval counts differ")
        if any(not isinstance(entry, GateControlEntry) for entry in self.entries):
            raise ScheduleValidationError("validated schedule contains a non-entry item")
        if any(type(ticks) is not int or ticks <= 0 for ticks in self.entry_interval_ticks):
            raise ScheduleValidationError("validated entry intervals must be positive ticks")
        if not isinstance(self.cycle_time, CycleTime):
            raise ScheduleValidationError("validated schedule must retain its rational CycleTime")
        try:
            expected_cycle_time_ns = self.cycle_time.exact_nanoseconds()
        except TimeConfigurationError as error:
            raise ScheduleValidationError(str(error)) from error
        if type(self.cycle_time_ns) is not int or self.cycle_time_ns != expected_cycle_time_ns:
            raise ScheduleValidationError("validated CycleTime nanoseconds do not match the rational value")
        if type(self.cycle_ticks) is not int or self.cycle_ticks <= 0:
            raise ScheduleValidationError("validated CycleTime must contain positive ticks")
        if type(self.total_interval_ns) is not int or self.total_interval_ns < 0:
            raise ScheduleValidationError("validated total interval must be non-negative")
        if self.total_interval_ns != sum(
            entry.effective_interval_ns for entry in self.entries
        ):
            raise ScheduleValidationError("validated total interval does not match entries")
        if (
            type(self.tick_granularity_x10_ns) is not int
            or not 10 <= self.tick_granularity_x10_ns <= UINT32_MAX
            or self.tick_granularity_x10_ns % 10 != 0
        ):
            raise ScheduleValidationError("validated TickGranularity is not an integer-ns uint32")
        tick_ns = self.tick_granularity_x10_ns // 10
        expected_cycle_ticks, cycle_remainder = divmod(self.cycle_time_ns, tick_ns)
        if cycle_remainder or self.cycle_ticks != expected_cycle_ticks:
            raise ScheduleValidationError("validated CycleTime ticks do not match TickGranularity")
        expected_entry_ticks = []
        for entry in self.entries:
            ticks, remainder = divmod(entry.effective_interval_ns, tick_ns)
            if remainder:
                raise ScheduleValidationError("validated entry is not aligned to TickGranularity")
            expected_entry_ticks.append(ticks)
        if tuple(expected_entry_ticks) != self.entry_interval_ticks:
            raise ScheduleValidationError("validated entry ticks do not match TimeIntervalValue")


def validate_schedule(
    entries: Iterable[GateControlEntry],
    cycle_time: CycleTime,
    timebase: Timebase,
    *,
    supported_list_max: int,
) -> ValidatedSchedule:
    if (
        type(supported_list_max) is not int
        or not 0 <= supported_list_max <= UINT32_MAX
    ):
        raise ScheduleValidationError("SupportedListMax must fit uint32")

    normalized_entries = tuple(entries)
    if any(not isinstance(entry, GateControlEntry) for entry in normalized_entries):
        raise ScheduleValidationError("every control-list item must be a GateControlEntry")
    if len(normalized_entries) > supported_list_max:
        raise ScheduleValidationError("AdminControlList exceeds SupportedListMax")

    try:
        cycle_time_ns = cycle_time.exact_nanoseconds()
        cycle_ticks = timebase.cycle_ticks(cycle_time)
        entry_interval_ticks = tuple(
            timebase.interval_ticks(entry.time_interval_ns)
            for entry in normalized_entries
        )
    except TimeConfigurationError as error:
        raise ScheduleValidationError(str(error)) from error

    total_interval_ns = sum(entry.effective_interval_ns for entry in normalized_entries)

    # The executor restarts the list at every cycle boundary. The standard
    # execution model therefore permits a list whose tail is preempted by the
    # next cycle; such entries are not silently removed from the configuration.
    return ValidatedSchedule(
        entries=normalized_entries,
        entry_interval_ticks=entry_interval_ticks,
        cycle_time=cycle_time,
        cycle_time_ns=cycle_time_ns,
        cycle_ticks=cycle_ticks,
        total_interval_ns=total_interval_ns,
        tick_granularity_x10_ns=timebase.tick_granularity_x10_ns,
    )


class ListExecutor:
    """Execute SetGateStates entries and hold the final state until cycle restart."""

    def __init__(self, *, timebase: Timebase) -> None:
        self._timebase = timebase
        self.gate_states = UINT8_MAX
        self.list_pointer = 0
        self.remaining_ticks: int | None = None
        self._schedule: ValidatedSchedule | None = None

    def initialize(self, admin_gate_states: int) -> None:
        """Apply AdminGateStates as the List Execute INIT state does."""
        if type(admin_gate_states) is not int or not 0 <= admin_gate_states <= UINT8_MAX:
            raise ScheduleValidationError("AdminGateStates must fit uint8")
        self.gate_states = admin_gate_states
        self.list_pointer = 0
        self.remaining_ticks = None
        self._schedule = None

    def start_cycle(self, schedule: ValidatedSchedule) -> None:
        if not isinstance(schedule, ValidatedSchedule):
            raise TypeError("start_cycle requires a ValidatedSchedule")
        if schedule.tick_granularity_x10_ns != self._timebase.tick_granularity_x10_ns:
            raise ScheduleValidationError(
                "schedule was validated for a different implementation timebase"
            )
        self._schedule = schedule
        self.list_pointer = 0
        self.remaining_ticks = None
        if not schedule.entries:
            return
        self._execute_entry(0)

    def advance_ticks(self, elapsed_ticks: int) -> int:
        if type(elapsed_ticks) is not int or elapsed_ticks < 0:
            raise ValueError("elapsed_ticks must be a non-negative integer")

        ticks_left = elapsed_ticks
        while ticks_left and self._schedule is not None and self.remaining_ticks is not None:
            if ticks_left < self.remaining_ticks:
                self.remaining_ticks -= ticks_left
                break

            ticks_left -= self.remaining_ticks
            next_pointer = self.list_pointer + 1
            if next_pointer >= len(self._schedule.entries):
                self.list_pointer = len(self._schedule.entries)
                self.remaining_ticks = None
                break
            self._execute_entry(next_pointer)

        return self.gate_states

    def _execute_entry(self, pointer: int) -> None:
        if self._schedule is None:
            raise RuntimeError("executor has no validated schedule")
        entry = self._schedule.entries[pointer]
        self.list_pointer = pointer
        self.gate_states = entry.gate_states
        self.remaining_ticks = self._schedule.entry_interval_ticks[pointer]
