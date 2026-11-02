from __future__ import annotations

import unittest

from tsn_qbv import (
    CycleTime,
    GateControlEntry,
    GateOperation,
    ListExecutor,
    ScheduleValidationError,
    Timebase,
    validate_schedule,
)


class ScheduleValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.timebase = Timebase(tick_granularity_x10_ns=10)
        self.cycle = CycleTime(numerator=1, denominator=8_000)

    def test_accepts_gcl_that_ends_before_cycle_end(self) -> None:
        schedule = validate_schedule(
            [GateControlEntry(GateOperation.SET_GATE_STATES, 0x0F, 25_000)],
            self.cycle,
            self.timebase,
            supported_list_max=8,
        )
        self.assertEqual(schedule.total_interval_ns, 25_000)
        self.assertEqual(schedule.cycle_time_ns, 125_000)

    def test_accepts_gcl_longer_than_cycle_and_preserves_all_entries(self) -> None:
        entries = [
            GateControlEntry(GateOperation.SET_GATE_STATES, 0x01, 75_000),
            GateControlEntry(GateOperation.SET_GATE_STATES, 0x02, 75_000),
        ]
        schedule = validate_schedule(
            entries, self.cycle, self.timebase, supported_list_max=8
        )
        self.assertEqual(len(schedule.entries), 2)
        self.assertEqual(schedule.total_interval_ns, 150_000)
        self.assertEqual(schedule.cycle_time_ns, 125_000)

    def test_rejects_list_over_capacity(self) -> None:
        entries = [GateControlEntry(GateOperation.SET_GATE_STATES, 0xFF, 0)] * 2
        with self.assertRaisesRegex(ScheduleValidationError, "SupportedListMax"):
            validate_schedule(entries, self.cycle, self.timebase, supported_list_max=1)

    def test_zero_interval_is_accepted_at_one_ns_granularity(self) -> None:
        schedule = validate_schedule(
            [GateControlEntry(GateOperation.SET_GATE_STATES, 0xFF, 0)],
            self.cycle,
            self.timebase,
            supported_list_max=8,
        )
        self.assertEqual(schedule.total_interval_ns, 1)

    def test_rejects_zero_interval_when_tick_is_coarse(self) -> None:
        coarse = Timebase(tick_granularity_x10_ns=80)
        with self.assertRaisesRegex(ScheduleValidationError, "TimeIntervalValue"):
            validate_schedule(
                [GateControlEntry(GateOperation.SET_GATE_STATES, 0xFF, 0)],
                self.cycle,
                coarse,
                supported_list_max=8,
            )

    def test_rejects_unsupported_gate_operation(self) -> None:
        with self.assertRaises(ScheduleValidationError):
            GateControlEntry(
                operation=1, gate_states=0xFF, time_interval_ns=100
            )

    def test_rejects_non_entry_items(self) -> None:
        with self.assertRaisesRegex(ScheduleValidationError, "GateControlEntry"):
            validate_schedule([object()], self.cycle, self.timebase, supported_list_max=8)

    def test_supported_list_max_must_fit_uint32(self) -> None:
        with self.assertRaisesRegex(ScheduleValidationError, "uint32"):
            validate_schedule([], self.cycle, self.timebase, supported_list_max=1 << 32)


class ListExecutorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.timebase = Timebase(tick_granularity_x10_ns=10)
        self.executor = ListExecutor(timebase=self.timebase)

    def schedule(self, entries):
        return validate_schedule(
            entries,
            CycleTime(numerator=1, denominator=8_000),
            self.timebase,
            supported_list_max=8,
        )

    def test_first_entry_applies_at_cycle_start(self) -> None:
        entries = [GateControlEntry(GateOperation.SET_GATE_STATES, 0x0F, 10)]
        self.executor.start_cycle(self.schedule(entries))
        self.assertEqual(self.executor.gate_states, 0x0F)
        self.assertEqual(self.executor.remaining_ticks, 10)

    def test_next_entry_applies_exactly_when_previous_interval_expires(self) -> None:
        entries = [
            GateControlEntry(GateOperation.SET_GATE_STATES, 0x0F, 10),
            GateControlEntry(GateOperation.SET_GATE_STATES, 0xF0, 20),
        ]
        self.executor.start_cycle(self.schedule(entries))
        self.executor.advance_ticks(9)
        self.assertEqual(self.executor.gate_states, 0x0F)
        self.executor.advance_ticks(1)
        self.assertEqual(self.executor.gate_states, 0xF0)
        self.assertEqual(self.executor.remaining_ticks, 20)

    def test_zero_interval_executes_for_one_nanosecond(self) -> None:
        entries = [
            GateControlEntry(GateOperation.SET_GATE_STATES, 0x01, 0),
            GateControlEntry(GateOperation.SET_GATE_STATES, 0x02, 10),
        ]
        self.executor.start_cycle(self.schedule(entries))
        self.assertEqual(self.executor.remaining_ticks, 1)
        self.executor.advance_ticks(1)
        self.assertEqual(self.executor.gate_states, 0x02)

    def test_end_of_list_holds_last_gate_state_until_next_cycle(self) -> None:
        entries = [GateControlEntry(GateOperation.SET_GATE_STATES, 0xA5, 10)]
        self.executor.start_cycle(self.schedule(entries))
        self.executor.advance_ticks(10)
        self.assertEqual(self.executor.gate_states, 0xA5)
        self.assertIsNone(self.executor.remaining_ticks)
        self.executor.advance_ticks(100)
        self.assertEqual(self.executor.gate_states, 0xA5)

    def test_new_cycle_preempts_the_previous_interval(self) -> None:
        entries = [GateControlEntry(GateOperation.SET_GATE_STATES, 0x0F, 100)]
        self.executor.start_cycle(self.schedule(entries))
        self.executor.advance_ticks(20)
        self.assertEqual(self.executor.remaining_ticks, 80)

        next_entries = [GateControlEntry(GateOperation.SET_GATE_STATES, 0xF0, 50)]
        self.executor.start_cycle(self.schedule(next_entries))
        self.assertEqual(self.executor.gate_states, 0xF0)
        self.assertEqual(self.executor.remaining_ticks, 50)

    def test_cycle_boundary_preempts_an_overlong_control_list(self) -> None:
        schedule = self.schedule([
            GateControlEntry(GateOperation.SET_GATE_STATES, 0x01, 75_000),
            GateControlEntry(GateOperation.SET_GATE_STATES, 0x02, 75_000),
        ])
        self.executor.start_cycle(schedule)
        self.executor.advance_ticks(75_000)
        self.assertEqual(self.executor.gate_states, 0x02)
        self.assertEqual(self.executor.remaining_ticks, 75_000)

        self.executor.advance_ticks(50_000)
        self.assertEqual(self.executor.gate_states, 0x02)
        self.assertEqual(self.executor.remaining_ticks, 25_000)

        self.executor.start_cycle(schedule)
        self.assertEqual(self.executor.gate_states, 0x01)
        self.assertEqual(self.executor.list_pointer, 0)
        self.assertEqual(self.executor.remaining_ticks, 75_000)

    def test_empty_list_preserves_the_current_gate_state(self) -> None:
        self.executor.start_cycle(self.schedule(
            [GateControlEntry(GateOperation.SET_GATE_STATES, 0x33, 10)]
        ))
        self.executor.start_cycle(self.schedule([]))
        self.assertEqual(self.executor.gate_states, 0x33)
        self.assertIsNone(self.executor.remaining_ticks)

    def test_schedule_must_match_executor_timebase(self) -> None:
        coarse = Timebase(tick_granularity_x10_ns=20)
        coarse_schedule = validate_schedule(
            [GateControlEntry(GateOperation.SET_GATE_STATES, 0x0F, 10)],
            CycleTime(numerator=1, denominator=8_000),
            Timebase(tick_granularity_x10_ns=10),
            supported_list_max=8,
        )
        executor = ListExecutor(timebase=coarse)
        with self.assertRaisesRegex(ScheduleValidationError, "different.*timebase"):
            executor.start_cycle(coarse_schedule)

    def test_initialize_applies_admin_gate_states_and_clears_execution(self) -> None:
        self.executor.start_cycle(self.schedule(
            [GateControlEntry(GateOperation.SET_GATE_STATES, 0x00, 10)]
        ))
        self.executor.initialize(0xA5)
        self.assertEqual(self.executor.gate_states, 0xA5)
        self.assertEqual(self.executor.list_pointer, 0)
        self.assertIsNone(self.executor.remaining_ticks)

    def test_initialize_rejects_gate_mask_outside_uint8(self) -> None:
        with self.assertRaisesRegex(ScheduleValidationError, "AdminGateStates"):
            self.executor.initialize(0x100)

    def test_empty_list_holds_admin_gate_states_after_initialization(self) -> None:
        self.executor.initialize(0x3C)
        self.executor.start_cycle(self.schedule([]))
        self.assertEqual(self.executor.gate_states, 0x3C)
        self.assertIsNone(self.executor.remaining_ticks)


if __name__ == "__main__":
    unittest.main()
