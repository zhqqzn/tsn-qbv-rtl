"""Exact integer-nanosecond time arithmetic for the Qbv implementation profile."""

from __future__ import annotations

from dataclasses import dataclass


UINT32_MAX = (1 << 32) - 1
PTP_SECONDS_MAX = (1 << 48) - 1
NANOSECONDS_PER_SECOND = 1_000_000_000
TENTHS_PER_NANOSECOND = 10


class TimeConfigurationError(ValueError):
    """A time value cannot be represented by the configured timebase."""


@dataclass(frozen=True, slots=True, order=True)
class PtpTime:
    """PTP timestamp using the management representation from IEEE 802.1AS."""

    seconds: int
    nanoseconds: int

    def __post_init__(self) -> None:
        if type(self.seconds) is not int or not 0 <= self.seconds <= PTP_SECONDS_MAX:
            raise TimeConfigurationError("seconds must fit the unsigned 48-bit PTP field")
        if (
            type(self.nanoseconds) is not int
            or not 0 <= self.nanoseconds < NANOSECONDS_PER_SECOND
        ):
            raise TimeConfigurationError("nanoseconds must be in the range [0, 10^9)")

    @property
    def total_nanoseconds(self) -> int:
        return self.seconds * NANOSECONDS_PER_SECOND + self.nanoseconds

    @classmethod
    def from_total_nanoseconds(cls, value: int) -> PtpTime:
        if type(value) is not int or value < 0:
            raise TimeConfigurationError("absolute PTP time must be a non-negative integer")
        seconds, nanoseconds = divmod(value, NANOSECONDS_PER_SECOND)
        return cls(seconds=seconds, nanoseconds=nanoseconds)


@dataclass(frozen=True, slots=True)
class CycleTime:
    """IEEE 802.1Q rational CycleTime, expressed in seconds."""

    numerator: int
    denominator: int

    def __post_init__(self) -> None:
        if type(self.numerator) is not int or not 0 < self.numerator <= UINT32_MAX:
            raise TimeConfigurationError("CycleTime numerator must be a non-zero uint32")
        if type(self.denominator) is not int or not 0 < self.denominator <= UINT32_MAX:
            raise TimeConfigurationError("CycleTime denominator must be a non-zero uint32")

    def exact_nanoseconds(self) -> int:
        numerator_ns = self.numerator * NANOSECONDS_PER_SECOND
        period_ns, remainder = divmod(numerator_ns, self.denominator)
        if remainder != 0:
            raise TimeConfigurationError(
                "CycleTime is not exactly representable at integer-nanosecond resolution"
            )
        if period_ns == 0:
            raise TimeConfigurationError("CycleTime must be at least one nanosecond")
        return period_ns


@dataclass(frozen=True, slots=True)
class Timebase:
    """Implementation timebase; TickGranularity is reported in tenths of ns."""

    tick_granularity_x10_ns: int

    def __post_init__(self) -> None:
        value = self.tick_granularity_x10_ns
        if type(value) is not int or not 0 < value <= UINT32_MAX:
            raise TimeConfigurationError("TickGranularity must be a non-zero uint32")
        if value % TENTHS_PER_NANOSECOND != 0:
            raise TimeConfigurationError(
                "this implementation profile supports integer-nanosecond ticks only"
            )

    @property
    def tick_granularity_ns(self) -> int:
        return self.tick_granularity_x10_ns // TENTHS_PER_NANOSECOND

    def duration_ticks(self, duration_ns: int, *, field_name: str) -> int:
        """Convert a non-negative duration without applying GCL-specific rules."""
        if type(duration_ns) is not int or not 0 <= duration_ns <= UINT32_MAX:
            raise TimeConfigurationError(f"{field_name} must fit uint32 nanoseconds")
        ticks, remainder = divmod(duration_ns, self.tick_granularity_ns)
        if remainder != 0:
            raise TimeConfigurationError(
                f"{field_name} is not exactly representable by TickGranularity"
            )
        return ticks

    def interval_ticks(self, time_interval_ns: int) -> int:
        """Convert TimeIntervalValue, applying Qbv's zero-to-1ns rule."""
        if type(time_interval_ns) is not int or not 0 <= time_interval_ns <= UINT32_MAX:
            raise TimeConfigurationError("TimeIntervalValue must fit uint32")
        effective_interval_ns = max(time_interval_ns, 1)
        return self.duration_ticks(
            effective_interval_ns,
            field_name="TimeIntervalValue",
        )

    def cycle_ticks(self, cycle_time: CycleTime) -> int:
        period_ns = cycle_time.exact_nanoseconds()
        ticks, remainder = divmod(period_ns, self.tick_granularity_ns)
        if remainder != 0:
            raise TimeConfigurationError(
                "CycleTime is not an integer multiple of TickGranularity"
            )
        if ticks == 0:
            raise TimeConfigurationError("CycleTime must contain at least one time tick")
        return ticks

    def require_aligned(self, target: PtpTime, reference: PtpTime) -> None:
        delta_ns = target.total_nanoseconds - reference.total_nanoseconds
        if delta_ns % self.tick_granularity_ns != 0:
            raise TimeConfigurationError(
                "PTP time is not aligned to the implementation timebase phase"
            )


def next_cycle_boundary(
    base_time: PtpTime,
    current_time: PtpTime,
    cycle_time: CycleTime,
    timebase: Timebase,
) -> PtpTime:
    """Return the first base-time-derived cycle boundary not earlier than now."""
    period_ns = cycle_time.exact_nanoseconds()
    if period_ns % timebase.tick_granularity_ns != 0:
        raise TimeConfigurationError(
            "CycleTime is not an integer multiple of TickGranularity"
        )

    timebase.require_aligned(base_time, current_time)
    delta_ns = current_time.total_nanoseconds - base_time.total_nanoseconds
    if delta_ns <= 0:
        return base_time

    cycle_index, remainder = divmod(delta_ns, period_ns)
    if remainder:
        cycle_index += 1
    boundary_ns = base_time.total_nanoseconds + cycle_index * period_ns
    boundary = PtpTime.from_total_nanoseconds(boundary_ns)
    timebase.require_aligned(boundary, current_time)
    return boundary


def config_change_time(
    admin_base_time: PtpTime,
    current_time: PtpTime,
    admin_cycle_time: CycleTime,
    timebase: Timebase,
) -> PtpTime:
    """Compute the next legal activation time for an administrative schedule."""
    timebase.cycle_ticks(admin_cycle_time)
    if admin_base_time >= current_time:
        timebase.require_aligned(admin_base_time, current_time)
        return admin_base_time
    return next_cycle_boundary(
        base_time=admin_base_time,
        current_time=current_time,
        cycle_time=admin_cycle_time,
        timebase=timebase,
    )


def select_cycle_start_time(
    oper_base_time: PtpTime,
    current_time: PtpTime,
    oper_cycle_time: CycleTime,
    oper_cycle_time_extension_ns: int,
    timebase: Timebase,
    *,
    config_pending: bool,
    config_change_time: PtpTime | None,
) -> PtpTime:
    """Implement the Qbv SetCycleStartTime selection rules a) through d)."""
    if (
        type(oper_cycle_time_extension_ns) is not int
        or not 0 <= oper_cycle_time_extension_ns <= UINT32_MAX
    ):
        raise TimeConfigurationError("CycleTimeExtension must fit uint32 nanoseconds")

    period_ns = oper_cycle_time.exact_nanoseconds()
    timebase.cycle_ticks(oper_cycle_time)
    timebase.duration_ticks(
        oper_cycle_time_extension_ns,
        field_name="CycleTimeExtension",
    )

    if not config_pending:
        return next_cycle_boundary(oper_base_time, current_time, oper_cycle_time, timebase)
    if config_change_time is None:
        raise TimeConfigurationError("ConfigChangeTime is required while ConfigPending")
    timebase.require_aligned(config_change_time, current_time)
    if config_change_time < current_time:
        raise TimeConfigurationError(
            "ConfigChangeTime must not precede CurrentTime while ConfigPending"
        )

    threshold_ns = (
        current_time.total_nanoseconds + period_ns + oper_cycle_time_extension_ns
    )
    if config_change_time.total_nanoseconds > threshold_ns:
        return next_cycle_boundary(oper_base_time, current_time, oper_cycle_time, timebase)

    return config_change_time
