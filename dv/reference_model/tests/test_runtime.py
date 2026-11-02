from __future__ import annotations

import random
import unittest

from tsn_qbv import (
    CycleTime,
    GateControlEntry,
    GateControlRuntime,
    GateOperation,
    PtpTime,
    RuntimeEventKind,
    ScheduleConfiguration,
    Timebase,
    validate_schedule,
)


class GateControlRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.timebase = Timebase(tick_granularity_x10_ns=10)
        self.start = PtpTime(100, 0)

    def config(
        self,
        *,
        base_offset_ns: int,
        cycle_ns: int,
        entries: list[tuple[int, int]],
        cycle_extension_ns: int = 0,
    ) -> ScheduleConfiguration:
        cycle = CycleTime(numerator=1, denominator=1_000_000_000 // cycle_ns)
        schedule = validate_schedule(
            [
                GateControlEntry(
                    GateOperation.SET_GATE_STATES,
                    gate_states,
                    interval_ns,
                )
                for gate_states, interval_ns in entries
            ],
            cycle,
            self.timebase,
            supported_list_max=16,
        )
        return ScheduleConfiguration(
            base_time=PtpTime.from_total_nanoseconds(
                self.start.total_nanoseconds + base_offset_ns
            ),
            schedule=schedule,
            cycle_time_extension_ns=cycle_extension_ns,
        )

    def runtime(
        self,
        *,
        oper: ScheduleConfiguration,
        admin: ScheduleConfiguration | None = None,
        gate_enabled: bool = True,
        admin_gate_states: int = 0xFF,
    ) -> GateControlRuntime:
        return GateControlRuntime(
            timebase=self.timebase,
            admin_config=admin or oper,
            oper_config=oper,
            current_time=self.start,
            gate_enabled=gate_enabled,
            admin_gate_states=admin_gate_states,
        )

    def kinds(self, events):
        return [event.kind for event in events]

    def test_initial_oper_schedule_starts_at_base_time(self) -> None:
        oper = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x0F, 40), (0xF0, 40)],
        )
        runtime = self.runtime(oper=oper)

        self.assertEqual(runtime.current_time, self.start)
        self.assertEqual(runtime.gate_states, 0x0F)
        self.assertEqual(runtime.list_pointer, 0)
        self.assertEqual(runtime.remaining_ticks, 40)
        self.assertEqual(
            self.kinds(runtime.initial_events),
            [
                RuntimeEventKind.CYCLE_STARTED,
                RuntimeEventKind.LIST_ENTRY_STARTED,
                RuntimeEventKind.GATE_STATES_CHANGED,
            ],
        )

    def test_advance_to_processes_every_gcl_event_and_holds_end_state(self) -> None:
        oper = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x0F, 40), (0xF0, 40)],
        )
        runtime = self.runtime(oper=oper)

        events = runtime.advance_to(PtpTime(100, 39))
        self.assertEqual(events, ())
        self.assertEqual(runtime.gate_states, 0x0F)
        self.assertEqual(runtime.remaining_ticks, 1)

        events = runtime.advance_to(PtpTime(100, 40))
        self.assertEqual(self.kinds(events), [
            RuntimeEventKind.LIST_ENTRY_STARTED,
            RuntimeEventKind.GATE_STATES_CHANGED,
        ])
        self.assertEqual(runtime.gate_states, 0xF0)
        self.assertEqual(runtime.remaining_ticks, 40)

        events = runtime.advance_to(PtpTime(100, 80))
        self.assertEqual(self.kinds(events), [RuntimeEventKind.LIST_COMPLETED])
        self.assertEqual(runtime.gate_states, 0xF0)
        self.assertIsNone(runtime.remaining_ticks)

    def test_cycle_start_preempts_gcl_expiry_at_same_timestamp(self) -> None:
        oper = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x0F, 100), (0xF0, 20)],
        )
        runtime = self.runtime(oper=oper)

        events = runtime.advance_to(PtpTime(100, 100))

        self.assertEqual(self.kinds(events), [
            RuntimeEventKind.CYCLE_STARTED,
            RuntimeEventKind.LIST_ENTRY_STARTED,
        ])
        self.assertEqual(runtime.gate_states, 0x0F)
        self.assertEqual(runtime.list_pointer, 0)
        self.assertEqual(runtime.remaining_ticks, 100)

    def test_pending_change_keeps_old_cycles_until_config_change_time(self) -> None:
        old = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x01, 100)],
        )
        new = self.config(
            base_offset_ns=250,
            cycle_ns=200,
            entries=[(0xA5, 60), (0x5A, 60)],
        )
        runtime = self.runtime(oper=old, admin=new)
        runtime.request_config_change()

        self.assertTrue(runtime.config_pending)
        self.assertEqual(runtime.next_cycle_start_time, PtpTime(100, 100))

        events = runtime.advance_to(PtpTime(100, 200))
        self.assertEqual(
            [event.scheduled_time for event in events if event.kind is RuntimeEventKind.CYCLE_STARTED],
            [PtpTime(100, 100), PtpTime(100, 200)],
        )
        self.assertTrue(runtime.config_pending)
        self.assertIs(runtime.oper_config, old)
        self.assertEqual(runtime.next_cycle_start_time, PtpTime(100, 250))

        events = runtime.advance_to(PtpTime(100, 250))
        self.assertEqual(self.kinds(events), [
            RuntimeEventKind.CONFIGURATION_ACTIVATED,
            RuntimeEventKind.CYCLE_STARTED,
            RuntimeEventKind.LIST_ENTRY_STARTED,
            RuntimeEventKind.GATE_STATES_CHANGED,
        ])
        self.assertIs(runtime.oper_config, new)
        self.assertEqual(runtime.gate_states, 0xA5)
        self.assertEqual(runtime.remaining_ticks, 60)
        self.assertEqual(runtime.next_cycle_start_time, PtpTime(100, 450))

    def test_cycle_extension_moves_next_start_to_config_change_time(self) -> None:
        old = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x01, 100)],
            cycle_extension_ns=20,
        )
        new = self.config(
            base_offset_ns=110,
            cycle_ns=100,
            entries=[(0x02, 50)],
        )
        runtime = self.runtime(oper=old, admin=new)
        runtime.request_config_change()

        self.assertEqual(runtime.next_cycle_start_time, PtpTime(100, 110))
        events = runtime.advance_to(PtpTime(100, 110))
        self.assertEqual(self.kinds(events), [
            RuntimeEventKind.LIST_COMPLETED,
            RuntimeEventKind.CONFIGURATION_ACTIVATED,
            RuntimeEventKind.CYCLE_STARTED,
            RuntimeEventKind.LIST_ENTRY_STARTED,
            RuntimeEventKind.GATE_STATES_CHANGED,
        ])
        self.assertEqual(runtime.gate_states, 0x02)
        self.assertIs(runtime.oper_config, new)

    def test_config_change_due_at_request_sample_activates_immediately(self) -> None:
        old = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x01, 100)],
        )
        new = self.config(
            base_offset_ns=0,
            cycle_ns=200,
            entries=[(0xA5, 50)],
        )
        runtime = self.runtime(oper=old, admin=new)

        events = runtime.request_config_change()

        self.assertEqual(self.kinds(events), [
            RuntimeEventKind.CONFIGURATION_ACTIVATED,
            RuntimeEventKind.CYCLE_STARTED,
            RuntimeEventKind.LIST_ENTRY_STARTED,
            RuntimeEventKind.GATE_STATES_CHANGED,
        ])
        self.assertIs(runtime.oper_config, new)
        self.assertFalse(runtime.config_pending)
        self.assertEqual(runtime.gate_states, 0xA5)
        self.assertEqual(runtime.remaining_ticks, 50)

    def test_configuration_activation_precedes_gcl_expiry_at_same_time(self) -> None:
        old = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x11, 40), (0x22, 40)],
        )
        new = self.config(
            base_offset_ns=40,
            cycle_ns=100,
            entries=[(0xAA, 20), (0xBB, 20)],
        )
        runtime = self.runtime(oper=old, admin=new)
        runtime.request_config_change()

        events = runtime.advance_to(PtpTime(100, 40))
        self.assertEqual(self.kinds(events), [
            RuntimeEventKind.CONFIGURATION_ACTIVATED,
            RuntimeEventKind.CYCLE_STARTED,
            RuntimeEventKind.LIST_ENTRY_STARTED,
            RuntimeEventKind.GATE_STATES_CHANGED,
        ])
        self.assertEqual(runtime.gate_states, 0xAA)
        self.assertIs(runtime.oper_config, new)

    def test_disabling_gate_enabled_cancels_pending_configuration(self) -> None:
        old = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x01, 100)],
        )
        new = self.config(
            base_offset_ns=150,
            cycle_ns=100,
            entries=[(0x02, 50)],
        )
        runtime = self.runtime(oper=old, admin=new)
        runtime.request_config_change()
        runtime.advance_to(PtpTime(100, 20))
        events = runtime.set_gate_enabled(False)
        self.assertEqual(self.kinds(events), [RuntimeEventKind.GATES_INITIALIZED])
        self.assertEqual(runtime.gate_states, 0xFF)
        self.assertFalse(runtime.config_pending)

        events = runtime.advance_to(PtpTime(100, 150))
        self.assertEqual(events, ())
        self.assertIs(runtime.oper_config, old)
        self.assertIsNone(runtime.next_cycle_start_time)

    def test_reenable_uses_oper_schedule_until_a_new_request(self) -> None:
        old = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x01, 100)],
        )
        new = self.config(
            base_offset_ns=150,
            cycle_ns=100,
            entries=[(0x02, 50)],
        )
        runtime = self.runtime(oper=old, admin=new)
        runtime.request_config_change()
        runtime.set_gate_enabled(False)
        runtime.advance_to(PtpTime(100, 150))
        self.assertIs(runtime.oper_config, old)

        events = runtime.set_gate_enabled(True)
        self.assertEqual(events, ())
        self.assertEqual(runtime.next_cycle_start_time, PtpTime(100, 200))

        events = runtime.request_config_change()
        self.assertEqual(self.kinds(events), [
            RuntimeEventKind.CONFIGURATION_ACTIVATED,
            RuntimeEventKind.CYCLE_STARTED,
            RuntimeEventKind.LIST_ENTRY_STARTED,
            RuntimeEventKind.GATE_STATES_CHANGED,
        ])
        self.assertIs(runtime.oper_config, new)
        self.assertEqual(runtime.gate_states, 0x02)

    def test_disabled_request_uses_latest_admin_when_gate_enabled(self) -> None:
        old = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x01, 100)],
        )
        new = self.config(
            base_offset_ns=200,
            cycle_ns=100,
            entries=[(0x02, 50)],
        )
        next_admin = self.config(
            base_offset_ns=300,
            cycle_ns=100,
            entries=[(0x03, 50)],
        )
        runtime = self.runtime(oper=old, admin=new, gate_enabled=False)
        runtime.request_config_change()
        runtime.set_admin_config(next_admin)
        self.assertTrue(runtime.config_change)
        self.assertFalse(runtime.config_pending)

        runtime.set_gate_enabled(True)
        self.assertTrue(runtime.config_pending)
        self.assertEqual(runtime.config_change_time, next_admin.base_time)
        runtime.advance_to(next_admin.base_time)
        self.assertIs(runtime.oper_config, next_admin)
        self.assertIs(runtime.admin_config, next_admin)

    def test_admin_gate_states_apply_on_disable_not_on_admin_write(self) -> None:
        oper = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x00, 100)],
        )
        runtime = self.runtime(oper=oper)
        runtime.set_admin_gate_states(0xA5)
        self.assertEqual(runtime.gate_states, 0x00)

        events = runtime.set_gate_enabled(False)
        self.assertEqual(self.kinds(events), [RuntimeEventKind.GATES_INITIALIZED])
        self.assertEqual(runtime.gate_states, 0xA5)

    def test_admin_gate_states_update_while_already_disabled(self) -> None:
        oper = self.config(base_offset_ns=0, cycle_ns=100, entries=[])
        runtime = self.runtime(oper=oper, gate_enabled=False)
        events = runtime.set_admin_gate_states(0x5A)
        self.assertEqual(self.kinds(events), [RuntimeEventKind.GATES_INITIALIZED])
        self.assertEqual(runtime.admin_gate_states, 0x5A)
        self.assertEqual(runtime.gate_states, 0x5A)

    def test_large_time_advance_processes_all_intermediate_cycles(self) -> None:
        oper = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0x01, 50), (0x02, 50)],
        )
        runtime = self.runtime(oper=oper)

        events = runtime.advance_to(PtpTime(100, 450))
        cycle_starts = [event for event in events if event.kind is RuntimeEventKind.CYCLE_STARTED]
        self.assertEqual(len(cycle_starts), 4)
        self.assertEqual(
            [event.scheduled_time for event in cycle_starts],
            [PtpTime(100, 100), PtpTime(100, 200), PtpTime(100, 300), PtpTime(100, 400)],
        )
        self.assertEqual(runtime.gate_states, 0x02)
        self.assertEqual(runtime.list_pointer, 1)
        self.assertEqual(runtime.remaining_ticks, 50)

    def test_event_jump_matches_one_tick_at_a_time_execution(self) -> None:
        cases = [
            (100, 250, [(0x01, 20), (0x02, 30), (0x04, 40)], 0),
            (125, 275, [(0x11, 25), (0x22, 50)], 10),
            (200, 450, [(0x0F, 250), (0xF0, 100)], 0),
            (250, 525, [(0xAA, 50), (0x55, 50), (0xFF, 50)], 25),
            (400, 650, [], 0),
        ]
        for old_cycle_ns, admin_base_offset, entries, extension_ns in cases:
            with self.subTest(old_cycle_ns=old_cycle_ns, admin_base=admin_base_offset):
                old = self.config(
                    base_offset_ns=0,
                    cycle_ns=old_cycle_ns,
                    entries=[(0x01, old_cycle_ns)] if not entries else entries,
                )
                admin = self.config(
                    base_offset_ns=admin_base_offset,
                    cycle_ns=125,
                    entries=[(0xA5, 25), (0x5A, 50)],
                    cycle_extension_ns=extension_ns,
                )
                stepped = self.runtime(oper=old, admin=admin)
                jumped = self.runtime(oper=old, admin=admin)
                stepped.request_config_change()
                jumped.request_config_change()

                step_events = []
                final_offset = admin_base_offset + 500
                for offset in range(1, final_offset + 1):
                    step_events.extend(
                        stepped.advance_to(PtpTime(100, offset))
                    )
                jump_events = jumped.advance_to(PtpTime(100, final_offset))

                self.assertEqual(tuple(step_events), jump_events)
                self.assertEqual(stepped.gate_states, jumped.gate_states)
                self.assertEqual(stepped.list_pointer, jumped.list_pointer)
                self.assertEqual(stepped.remaining_ticks, jumped.remaining_ticks)
                self.assertEqual(stepped.next_cycle_start_time, jumped.next_cycle_start_time)
                self.assertEqual(stepped.config_pending, jumped.config_pending)
                self.assertEqual(stepped.oper_config, jumped.oper_config)
                self.assertEqual(stepped.config_change_error, jumped.config_change_error)

    def test_randomized_event_jumps_match_tick_stepping(self) -> None:
        rng = random.Random(0x8021_1CB)
        cycle_choices = (50, 100, 125, 200, 250, 400, 500)

        for case_index in range(40):
            old_cycle_ns = rng.choice(cycle_choices)
            new_cycle_ns = rng.choice(cycle_choices)
            admin_base_offset = rng.randint(1, 400)
            extension_ns = rng.randint(0, 50)
            old_entries = [
                (rng.randrange(256), rng.randint(1, 100))
                for _ in range(rng.randint(0, 4))
            ]
            new_entries = [
                (rng.randrange(256), rng.randint(1, 100))
                for _ in range(rng.randint(0, 4))
            ]

            with self.subTest(case=case_index):
                old = self.config(
                    base_offset_ns=0,
                    cycle_ns=old_cycle_ns,
                    entries=old_entries,
                )
                admin = self.config(
                    base_offset_ns=admin_base_offset,
                    cycle_ns=new_cycle_ns,
                    entries=new_entries,
                    cycle_extension_ns=extension_ns,
                )
                stepped = self.runtime(oper=old, admin=admin)
                jumped = self.runtime(oper=old, admin=admin)
                stepped.request_config_change()
                jumped.request_config_change()

                target_offset = admin_base_offset + 500
                step_events = []
                for offset in range(1, target_offset + 1):
                    step_events.extend(stepped.advance_to(PtpTime(100, offset)))
                jump_events = jumped.advance_to(PtpTime(100, target_offset))

                self.assertEqual(tuple(step_events), jump_events)
                self.assertEqual(stepped.gate_states, jumped.gate_states)
                self.assertEqual(stepped.list_pointer, jumped.list_pointer)
                self.assertEqual(stepped.remaining_ticks, jumped.remaining_ticks)
                self.assertEqual(stepped.next_cycle_start_time, jumped.next_cycle_start_time)
                self.assertEqual(stepped.config_pending, jumped.config_pending)
                self.assertEqual(stepped.oper_config, jumped.oper_config)
                self.assertEqual(stepped.config_change_error, jumped.config_change_error)

    def test_advance_to_rejects_backwards_and_off_grid_time(self) -> None:
        oper = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0xFF, 100)],
        )
        runtime = self.runtime(oper=oper)
        runtime.advance_to(PtpTime(100, 50))
        with self.assertRaisesRegex(ValueError, "move backwards"):
            runtime.advance_to(PtpTime(100, 49))

        coarse_timebase = Timebase(tick_granularity_x10_ns=80)
        coarse_schedule = validate_schedule(
            [GateControlEntry(GateOperation.SET_GATE_STATES, 0xFF, 8)],
            CycleTime(1, 8_000),
            coarse_timebase,
            supported_list_max=8,
        )
        coarse_config = ScheduleConfiguration(self.start, coarse_schedule)
        coarse_runtime = GateControlRuntime(
            timebase=coarse_timebase,
            admin_config=coarse_config,
            oper_config=coarse_config,
            current_time=self.start,
            gate_enabled=True,
        )
        with self.assertRaisesRegex(ValueError, "phase"):
            coarse_runtime.advance_to(PtpTime(100, 1))

    def test_admin_gate_states_rejects_values_outside_uint8(self) -> None:
        oper = self.config(
            base_offset_ns=0,
            cycle_ns=100,
            entries=[(0xFF, 100)],
        )
        runtime = self.runtime(oper=oper)
        with self.assertRaisesRegex(ValueError, "AdminGateStates"):
            runtime.set_admin_gate_states(0x100)


if __name__ == "__main__":
    unittest.main()
