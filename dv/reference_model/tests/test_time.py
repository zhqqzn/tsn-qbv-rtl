from __future__ import annotations

import unittest

from tsn_qbv import (
    CycleTime,
    PtpTime,
    TimeConfigurationError,
    Timebase,
    config_change_time,
    next_cycle_boundary,
    select_cycle_start_time,
)


class PtpTimeTests(unittest.TestCase):
    def test_round_trip_at_second_boundary(self) -> None:
        value = PtpTime(seconds=17, nanoseconds=999_999_999)
        self.assertEqual(PtpTime.from_total_nanoseconds(value.total_nanoseconds), value)

    def test_rejects_nanoseconds_outside_ptp_range(self) -> None:
        with self.assertRaises(TimeConfigurationError):
            PtpTime(seconds=0, nanoseconds=1_000_000_000)

    def test_rejects_seconds_overflow(self) -> None:
        with self.assertRaises(TimeConfigurationError):
            PtpTime(seconds=1 << 48, nanoseconds=0)

    def test_rejects_absolute_time_overflow(self) -> None:
        with self.assertRaises(TimeConfigurationError):
            PtpTime.from_total_nanoseconds((1 << 48) * 1_000_000_000)


class TimebaseTests(unittest.TestCase):
    def test_reports_tick_granularity_in_tenths_of_ns(self) -> None:
        timebase = Timebase(tick_granularity_x10_ns=80)
        self.assertEqual(timebase.tick_granularity_ns, 8)

    def test_rejects_subnanosecond_tick_in_v1_profile(self) -> None:
        with self.assertRaises(TimeConfigurationError):
            Timebase(tick_granularity_x10_ns=5)

    def test_zero_interval_is_one_nanosecond(self) -> None:
        timebase = Timebase(tick_granularity_x10_ns=10)
        self.assertEqual(timebase.interval_ticks(0), 1)

    def test_zero_interval_is_rejected_when_tick_is_coarser_than_one_ns(self) -> None:
        timebase = Timebase(tick_granularity_x10_ns=20)
        with self.assertRaises(TimeConfigurationError):
            timebase.interval_ticks(0)

    def test_nonzero_interval_must_be_tick_aligned(self) -> None:
        timebase = Timebase(tick_granularity_x10_ns=80)
        self.assertEqual(timebase.interval_ticks(64), 8)
        with self.assertRaises(TimeConfigurationError):
            timebase.interval_ticks(65)

    def test_cycle_time_is_converted_without_floating_point(self) -> None:
        timebase = Timebase(tick_granularity_x10_ns=80)
        cycle = CycleTime(numerator=1, denominator=8_000)
        self.assertEqual(cycle.exact_nanoseconds(), 125_000)
        self.assertEqual(timebase.cycle_ticks(cycle), 15_625)

    def test_cycle_time_fractional_nanosecond_is_rejected(self) -> None:
        with self.assertRaises(TimeConfigurationError):
            CycleTime(numerator=1, denominator=3).exact_nanoseconds()

    def test_cycle_time_must_align_to_tick_granularity(self) -> None:
        timebase = Timebase(tick_granularity_x10_ns=80)
        # 100001 ns is exact at integer-nanosecond resolution, but it is not
        # representable on an 8 ns implementation timebase.
        with self.assertRaises(TimeConfigurationError):
            timebase.cycle_ticks(CycleTime(numerator=100_001, denominator=1_000_000_000))


class CycleBoundaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.timebase = Timebase(tick_granularity_x10_ns=10)
        self.cycle = CycleTime(numerator=1, denominator=8_000)
        self.base = PtpTime(seconds=100, nanoseconds=0)

    def test_future_base_time_is_returned_unchanged(self) -> None:
        now = PtpTime(seconds=99, nanoseconds=900_000_000)
        self.assertEqual(
            next_cycle_boundary(self.base, now, self.cycle, self.timebase),
            self.base,
        )

    def test_past_base_time_uses_smallest_future_cycle_index(self) -> None:
        now = PtpTime(seconds=100, nanoseconds=300_000)
        expected = PtpTime(seconds=100, nanoseconds=375_000)
        self.assertEqual(
            next_cycle_boundary(self.base, now, self.cycle, self.timebase),
            expected,
        )

    def test_exact_boundary_is_not_advanced_by_an_extra_cycle(self) -> None:
        now = PtpTime(seconds=100, nanoseconds=250_000)
        self.assertEqual(
            next_cycle_boundary(self.base, now, self.cycle, self.timebase),
            now,
        )

    def test_base_time_must_match_timebase_phase(self) -> None:
        coarse_timebase = Timebase(tick_granularity_x10_ns=80)
        now = PtpTime(seconds=100, nanoseconds=1)
        with self.assertRaises(TimeConfigurationError):
            next_cycle_boundary(self.base, now, self.cycle, coarse_timebase)

    def test_boundary_overflow_is_rejected(self) -> None:
        base = PtpTime(seconds=(1 << 48) - 1, nanoseconds=999_900_000)
        now = PtpTime(seconds=(1 << 48) - 1, nanoseconds=999_950_000)
        with self.assertRaises(TimeConfigurationError):
            next_cycle_boundary(base, now, self.cycle, self.timebase)

    def test_config_change_time_uses_admin_cycle(self) -> None:
        now = PtpTime(seconds=100, nanoseconds=300_000)
        self.assertEqual(
            config_change_time(self.base, now, self.cycle, self.timebase),
            PtpTime(seconds=100, nanoseconds=375_000),
        )

    def test_cycle_start_waits_for_old_cycle_when_change_is_far_away(self) -> None:
        now = PtpTime(seconds=100, nanoseconds=1)
        old_cycle = CycleTime(numerator=1, denominator=10_000)
        change_time = PtpTime(seconds=100, nanoseconds=300_000)
        selected = select_cycle_start_time(
            oper_base_time=self.base,
            current_time=now,
            oper_cycle_time=old_cycle,
            oper_cycle_time_extension_ns=0,
            timebase=self.timebase,
            config_pending=True,
            config_change_time=change_time,
        )
        self.assertEqual(selected, PtpTime(seconds=100, nanoseconds=100_000))

    def test_pending_config_change_time_cannot_be_in_the_past(self) -> None:
        with self.assertRaisesRegex(TimeConfigurationError, "must not precede CurrentTime"):
            select_cycle_start_time(
                oper_base_time=self.base,
                current_time=PtpTime(seconds=100, nanoseconds=100_000),
                oper_cycle_time=self.cycle,
                oper_cycle_time_extension_ns=0,
                timebase=self.timebase,
                config_pending=True,
                config_change_time=PtpTime(seconds=100, nanoseconds=99_999),
            )

    def test_cycle_start_uses_config_time_inside_cycle_extension_window(self) -> None:
        now = PtpTime(seconds=100, nanoseconds=0)
        old_cycle = CycleTime(numerator=1, denominator=10_000)
        change_time = PtpTime(seconds=100, nanoseconds=150_000)
        selected = select_cycle_start_time(
            oper_base_time=self.base,
            current_time=now,
            oper_cycle_time=old_cycle,
            oper_cycle_time_extension_ns=50_000,
            timebase=self.timebase,
            config_pending=True,
            config_change_time=change_time,
        )
        self.assertEqual(selected, change_time)

    def test_cycle_extension_must_align_to_timebase(self) -> None:
        coarse_timebase = Timebase(tick_granularity_x10_ns=80)
        with self.assertRaisesRegex(TimeConfigurationError, "CycleTimeExtension"):
            select_cycle_start_time(
                oper_base_time=self.base,
                current_time=self.base,
                oper_cycle_time=self.cycle,
                oper_cycle_time_extension_ns=1,
                timebase=coarse_timebase,
                config_pending=False,
                config_change_time=None,
            )

    def test_pending_config_time_must_align_to_timebase(self) -> None:
        change_time = PtpTime(seconds=100, nanoseconds=1)
        coarse_timebase = Timebase(tick_granularity_x10_ns=80)
        with self.assertRaisesRegex(TimeConfigurationError, "phase"):
            select_cycle_start_time(
                oper_base_time=self.base,
                current_time=self.base,
                oper_cycle_time=self.cycle,
                oper_cycle_time_extension_ns=0,
                timebase=coarse_timebase,
                config_pending=True,
                config_change_time=change_time,
            )

    def test_pending_config_requires_config_change_time(self) -> None:
        with self.assertRaises(TimeConfigurationError):
            select_cycle_start_time(
                oper_base_time=self.base,
                current_time=self.base,
                oper_cycle_time=self.cycle,
                oper_cycle_time_extension_ns=0,
                timebase=self.timebase,
                config_pending=True,
                config_change_time=None,
            )


if __name__ == "__main__":
    unittest.main()
