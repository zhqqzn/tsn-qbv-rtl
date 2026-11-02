"""Transactional Admin/Oper configuration model for the Qbv profile."""

from __future__ import annotations

from dataclasses import dataclass

from .execution import ScheduleValidationError, ValidatedSchedule
from .time import (
    PtpTime,
    Timebase,
    TimeConfigurationError,
    config_change_time,
    next_cycle_boundary,
    select_cycle_start_time,
)

UINT32_MAX = (1 << 32) - 1


class ConfigurationBusyError(RuntimeError):
    """A configuration-change request is already latched or pending."""


class ConfigurationStateError(RuntimeError):
    """A configuration operation is invalid in the current controller state."""


@dataclass(frozen=True, slots=True)
class ScheduleConfiguration:
    """Immutable complete set of Admin/Oper parameters owned by this port."""

    base_time: PtpTime
    schedule: ValidatedSchedule
    cycle_time_extension_ns: int = 0

    def __post_init__(self) -> None:
        if not isinstance(self.base_time, PtpTime):
            raise ScheduleValidationError("BaseTime must be a PtpTime")
        if not isinstance(self.schedule, ValidatedSchedule):
            raise ScheduleValidationError("schedule must be a ValidatedSchedule")
        if (
            type(self.cycle_time_extension_ns) is not int
            or not 0 <= self.cycle_time_extension_ns <= UINT32_MAX
        ):
            raise ScheduleValidationError("CycleTimeExtension must fit uint32 nanoseconds")

    def validate_for(self, timebase: Timebase) -> None:
        if self.schedule.tick_granularity_x10_ns != timebase.tick_granularity_x10_ns:
            raise ScheduleValidationError(
                "schedule was validated for a different implementation timebase"
            )
        try:
            timebase.duration_ticks(
                self.cycle_time_extension_ns,
                field_name="CycleTimeExtension",
            )
        except TimeConfigurationError as error:
            raise ScheduleValidationError(str(error)) from error


@dataclass(frozen=True, slots=True)
class ConfigurationActivation:
    """Atomic Admin-to-Oper transition and Cycle Timer handoff.

    Activation is valid only at exact equality between CurrentTime and
    ConfigChangeTime. The cycle-start decision is captured while ConfigPending
    is still true, before the controller clears its pending state.
    """

    previous: ScheduleConfiguration | None
    active: ScheduleConfiguration
    config_change_time: PtpTime
    activation_time: PtpTime
    cycle_start_time: PtpTime | None


class ConfigurationController:
    """Own the Admin/Oper transition and serialize it with cycle execution.

    A ConfigChange request remains a level while GateEnabled is false. It is
    accepted into CONFIG_PENDING only when GateEnabled is true; the Admin image
    and ConfigChangeTime are captured at that acceptance point. The single
    Admin image is write-locked while ConfigPending is true, then becomes
    writable again after activation. Only one request may be latched/pending.

    List Config follows the IEEE 802.1Q-2022 maintenance correction for item
    0319: CONFIG_PENDING transitions to UPDATE_CONFIG only when
    ConfigChangeTime equals CurrentTime. Clearing GateEnabled before that
    instant cancels the accepted update. At the exact instant the complete
    operational configuration is installed and the Cycle Timer handoff is
    captured as one model event.
    """

    def __init__(
        self,
        *,
        timebase: Timebase,
        admin_config: ScheduleConfiguration,
        oper_config: ScheduleConfiguration | None = None,
        gate_enabled: bool = False,
    ) -> None:
        if not isinstance(timebase, Timebase):
            raise TypeError("timebase must be a Timebase")
        if type(gate_enabled) is not bool:
            raise TypeError("gate_enabled must be bool")
        admin_config.validate_for(timebase)
        if oper_config is not None:
            oper_config.validate_for(timebase)

        self._timebase = timebase
        self._admin_config = admin_config
        self._oper_config = oper_config
        self._gate_enabled = gate_enabled
        self._config_change_latched = False
        self._pending_config: ScheduleConfiguration | None = None
        self._config_pending = False
        self._config_change_time: PtpTime | None = None
        self._config_change_error = 0
        self._last_observed_time: PtpTime | None = None

    @property
    def admin_config(self) -> ScheduleConfiguration:
        return self._admin_config

    @property
    def oper_config(self) -> ScheduleConfiguration | None:
        return self._oper_config

    @property
    def gate_enabled(self) -> bool:
        return self._gate_enabled

    @property
    def config_change(self) -> bool:
        """The management request has not yet been accepted by List Config."""
        return self._config_change_latched

    @property
    def config_pending(self) -> bool:
        return self._config_pending

    @property
    def config_change_time(self) -> PtpTime | None:
        return self._config_change_time

    @property
    def config_change_error(self) -> int:
        return self._config_change_error

    @property
    def pending_config(self) -> ScheduleConfiguration | None:
        return self._pending_config

    def set_admin_config(self, config: ScheduleConfiguration) -> None:
        """Replace Admin before acceptance or after its pending commit completes."""
        if self._config_pending:
            raise ConfigurationBusyError(
                "Admin configuration is locked while ConfigPending is true"
            )
        if not isinstance(config, ScheduleConfiguration):
            raise TypeError("config must be a ScheduleConfiguration")
        config.validate_for(self._timebase)
        self._admin_config = config

    def request_config_change(self, current_time: PtpTime) -> None:
        """Set ConfigChange; capture Admin only when GateEnabled accepts it."""
        self._observe_time(current_time)
        if self._config_change_latched or self._config_pending:
            raise ConfigurationBusyError("a configuration change is already in progress")

        if self._gate_enabled:
            self._begin_pending(self._admin_config, current_time)
        else:
            # CONFIG_IDLE does not consume ConfigChange while GateEnabled is
            # false. Admin remains writable; snapshot only when accepted.
            self._config_change_latched = True

    def set_gate_enabled(self, enabled: bool, current_time: PtpTime) -> None:
        """Enable/disable the state machines and accept a previously latched request."""
        if type(enabled) is not bool:
            raise TypeError("enabled must be bool")
        self._observe_time(current_time)
        was_enabled = self._gate_enabled
        self._gate_enabled = enabled
        if was_enabled and not enabled and self._config_pending:
            # Figure 8-16 has a global !GateEnabled transition from
            # CONFIG_PENDING to CONFIG_IDLE, which clears ConfigPending.
            self._pending_config = None
            self._config_pending = False
        elif enabled and not was_enabled and self._config_change_latched:
            self._begin_pending(self._admin_config, current_time)

    def cancel_latched_request(self) -> None:
        """Cancel a ConfigChange request that List Config has not accepted."""
        if not self._config_change_latched:
            raise ConfigurationStateError("there is no unaccepted request to cancel")
        self._config_change_latched = False

    def advance_time(self, current_time: PtpTime) -> ConfigurationActivation | None:
        """Process the List Config transition at the supplied PTP time sample."""
        self._observe_time(current_time)

        if self._config_change_latched and self._gate_enabled:
            self._begin_pending(self._admin_config, current_time)

        if not self._config_pending:
            return None
        if self._pending_config is None or self._config_change_time is None:
            raise ConfigurationStateError("ConfigPending lacks its snapshot or ConfigChangeTime")
        if current_time < self._config_change_time:
            return None
        previous = self._oper_config
        active = self._pending_config
        scheduled_time = self._config_change_time
        cycle_start_time: PtpTime | None = None
        if self._gate_enabled:
            if previous is None:
                cycle_start_time = scheduled_time
            else:
                try:
                    cycle_start_time = select_cycle_start_time(
                        oper_base_time=previous.base_time,
                        current_time=current_time,
                        oper_cycle_time=previous.schedule.cycle_time,
                        oper_cycle_time_extension_ns=previous.cycle_time_extension_ns,
                        timebase=self._timebase,
                        config_pending=True,
                        config_change_time=scheduled_time,
                    )
                except TimeConfigurationError as error:
                    raise ScheduleValidationError(str(error)) from error

        # One atomic model transition: all Oper fields change together, and
        # ConfigPending is cleared in the same event. The cycle-start decision
        # above is captured before clearing ConfigPending, avoiding the
        # List Config/Cycle Timer ordering race in the published state machines.
        self._oper_config = active
        self._pending_config = None
        self._config_pending = False
        self._config_change_latched = False

        return ConfigurationActivation(
            previous=previous,
            active=active,
            config_change_time=scheduled_time,
            activation_time=current_time,
            cycle_start_time=cycle_start_time,
        )

    def next_cycle_start_time(self, current_time: PtpTime) -> PtpTime | None:
        """Return the next cycle start without advancing controller state.

        Cycle Timer queries may evaluate a future representable sample to avoid
        selecting the cycle boundary that has just been consumed. Such a
        query must not advance the List Config machine's CurrentTime; only
        ``advance_time`` and management operations observe time.
        """
        if not isinstance(current_time, PtpTime):
            raise TypeError("current_time must be a PtpTime")
        previous = self._last_observed_time
        if previous is not None:
            if current_time < previous:
                raise TimeConfigurationError("CurrentTime must not move backwards")
            self._timebase.require_aligned(current_time, previous)
        if not self._gate_enabled or self._oper_config is None:
            return None

        oper = self._oper_config
        try:
            if self._config_pending:
                if self._config_change_time is None:
                    raise ConfigurationStateError(
                        "ConfigPending lacks ConfigChangeTime"
                    )
                if current_time > self._config_change_time:
                    raise ConfigurationStateError(
                        "ConfigChangeTime must be observed at exact timestamp equality"
                    )
                return select_cycle_start_time(
                    oper_base_time=oper.base_time,
                    current_time=current_time,
                    oper_cycle_time=oper.schedule.cycle_time,
                    oper_cycle_time_extension_ns=oper.cycle_time_extension_ns,
                    timebase=self._timebase,
                    config_pending=True,
                    config_change_time=self._config_change_time,
                )
            return next_cycle_boundary(
                oper.base_time,
                current_time,
                oper.schedule.cycle_time,
                self._timebase,
            )
        except TimeConfigurationError as error:
            raise ScheduleValidationError(str(error)) from error

    def _begin_pending(
        self,
        snapshot: ScheduleConfiguration,
        current_time: PtpTime,
    ) -> None:
        snapshot.validate_for(self._timebase)
        try:
            change_time = config_change_time(
                admin_base_time=snapshot.base_time,
                current_time=current_time,
                admin_cycle_time=snapshot.schedule.cycle_time,
                timebase=self._timebase,
            )
        except TimeConfigurationError as error:
            raise ScheduleValidationError(str(error)) from error

        if snapshot.base_time < current_time:
            # IEEE 802.1Qbv-2015 clause 8.6.9.3.1 uses GateEnabled here.
            # The maintenance request to use CurrentSchedule is not silently
            # adopted; that policy can be revisited against a later amendment.
            self._config_change_error += 1

        self._config_change_latched = False
        self._config_pending = True
        self._pending_config = snapshot
        self._config_change_time = change_time

    def _observe_time(self, current_time: PtpTime) -> None:
        if not isinstance(current_time, PtpTime):
            raise TypeError("current_time must be a PtpTime")
        previous = self._last_observed_time
        if previous is not None:
            if current_time < previous:
                raise TimeConfigurationError("CurrentTime must not move backwards")
            self._timebase.require_aligned(current_time, previous)
        if (
            self._config_pending
            and self._config_change_time is not None
            and current_time > self._config_change_time
        ):
            raise ConfigurationStateError(
                "ConfigChangeTime must be observed at exact timestamp equality"
            )
        self._last_observed_time = current_time
