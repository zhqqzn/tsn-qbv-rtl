from __future__ import annotations

import unittest

from tsn_qbv import (
    ConfigurationBusyError,
    ConfigurationController,
    CycleTime,
    GateControlEntry,
    GateOperation,
    PtpTime,
    ScheduleConfiguration,
    ScheduleValidationError,
    Timebase,
    validate_schedule,
)
from tsn_qbv.time import TimeConfigurationError


class ConfigurationControllerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.timebase = Timebase(tick_granularity_x10_ns=10)
        self.old_config = self.config(
            base_time=PtpTime(100, 0),
            cycle=CycleTime(1, 10_000),
            gate_states=0xFF,
        )
        self.new_config = self.config(
            base_time=PtpTime(100, 500_000),
            cycle=CycleTime(1, 8_000),
            gate_states=0x0F,
        )
        self.controller = ConfigurationController(
            timebase=self.timebase,
            admin_config=self.new_config,
            oper_config=self.old_config,
            gate_enabled=True,
        )

    def config(self, *, base_time, cycle, gate_states, extension=0):
        schedule = validate_schedule(
            [
                GateControlEntry(GateOperation.SET_GATE_STATES, gate_states, 10_000),
                GateControlEntry(GateOperation.SET_GATE_STATES, 0x00, 20_000),
            ],
            cycle,
            self.timebase,
            supported_list_max=16,
        )
        return ScheduleConfiguration(
            base_time=base_time,
            schedule=schedule,
            cycle_time_extension_ns=extension,
        )

    def test_request_is_pending_until_config_change_time(self) -> None:
        now = PtpTime(100, 0)
        self.controller.request_config_change(now)

        self.assertFalse(self.controller.config_change)
        self.assertTrue(self.controller.config_pending)
        self.assertEqual(self.controller.config_change_time, self.new_config.base_time)
        self.assertIs(self.controller.oper_config, self.old_config)
        self.assertIs(self.controller.pending_config, self.new_config)

        self.assertIsNone(self.controller.advance_time(PtpTime(100, 499_999)))
        self.assertIs(self.controller.oper_config, self.old_config)

        activation = self.controller.advance_time(PtpTime(100, 500_000))
        self.assertIsNotNone(activation)
        self.assertIs(activation.previous, self.old_config)
        self.assertIs(activation.active, self.new_config)
        self.assertEqual(activation.config_change_time, PtpTime(100, 500_000))
        self.assertEqual(activation.activation_time, PtpTime(100, 500_000))
        self.assertEqual(activation.cycle_start_time, PtpTime(100, 500_000))
        self.assertIs(self.controller.oper_config, self.new_config)
        self.assertFalse(self.controller.config_pending)
        self.assertIsNone(self.controller.pending_config)

    def test_admin_write_is_rejected_until_pending_configuration_activates(self) -> None:
        self.controller.request_config_change(PtpTime(100, 0))
        second_admin = self.config(
            base_time=PtpTime(101, 0),
            cycle=CycleTime(1, 4_000),
            gate_states=0xAA,
        )

        with self.assertRaisesRegex(ConfigurationBusyError, "locked while ConfigPending"):
            self.controller.set_admin_config(second_admin)
        self.assertIs(self.controller.admin_config, self.new_config)
        self.assertIs(self.controller.pending_config, self.new_config)

        activation = self.controller.advance_time(PtpTime(100, 500_000))
        self.assertIsNotNone(activation)
        self.assertIs(self.controller.oper_config, self.new_config)

        self.controller.set_admin_config(second_admin)
        self.assertIs(self.controller.admin_config, second_admin)
        self.assertIs(self.controller.oper_config, self.new_config)

    def test_admin_image_can_be_committed_again_after_previous_activation(self) -> None:
        self.controller.request_config_change(PtpTime(100, 0))
        first_activation = self.controller.advance_time(PtpTime(100, 500_000))
        self.assertIsNotNone(first_activation)

        second_admin = self.config(
            base_time=PtpTime(101, 0),
            cycle=CycleTime(1, 4_000),
            gate_states=0xAA,
        )
        self.controller.set_admin_config(second_admin)
        self.controller.request_config_change(PtpTime(100, 500_000))
        self.assertEqual(self.controller.config_change_time, PtpTime(101, 0))
        second_activation = self.controller.advance_time(PtpTime(101, 0))

        self.assertIsNotNone(second_activation)
        self.assertIs(second_activation.previous, self.new_config)
        self.assertIs(second_activation.active, second_admin)
        self.assertIs(self.controller.oper_config, second_admin)

    def test_second_request_is_rejected_while_first_is_pending(self) -> None:
        self.controller.request_config_change(PtpTime(100, 0))
        with self.assertRaises(ConfigurationBusyError):
            self.controller.request_config_change(PtpTime(100, 1))

    def test_request_while_disabled_is_latched_until_enable(self) -> None:
        controller = ConfigurationController(
            timebase=self.timebase,
            admin_config=self.new_config,
            oper_config=self.old_config,
            gate_enabled=False,
        )
        controller.request_config_change(PtpTime(100, 0))

        self.assertTrue(controller.config_change)
        self.assertFalse(controller.config_pending)
        self.assertIsNone(controller.config_change_time)
        self.assertIs(controller.oper_config, self.old_config)

        # While GateEnabled is false, ConfigChange remains unaccepted and
        # Admin remains writable. The most recent Admin image is captured
        # when GateEnabled becomes true and CONFIG_PENDING is entered.
        next_admin = self.config(
            base_time=PtpTime(101, 0),
            cycle=CycleTime(1, 4_000),
            gate_states=0x55,
        )
        controller.set_admin_config(next_admin)
        controller.set_gate_enabled(True, PtpTime(100, 100))

        self.assertFalse(controller.config_change)
        self.assertTrue(controller.config_pending)
        self.assertEqual(controller.config_change_time, next_admin.base_time)
        self.assertIs(controller.pending_config, next_admin)

        activation = controller.advance_time(next_admin.base_time)
        self.assertIsNotNone(activation)
        self.assertEqual(activation.cycle_start_time, next_admin.base_time)
        self.assertIs(controller.oper_config, next_admin)
        self.assertIs(controller.admin_config, next_admin)

    def test_disabling_gate_enabled_cancels_pending_configuration(self) -> None:
        self.controller.request_config_change(PtpTime(100, 0))
        self.controller.set_gate_enabled(False, PtpTime(100, 100))

        self.assertFalse(self.controller.config_pending)
        self.assertFalse(self.controller.config_change)
        self.assertIsNone(self.controller.pending_config)
        self.assertEqual(self.controller.config_change_time, self.new_config.base_time)
        self.assertIs(self.controller.oper_config, self.old_config)
        self.assertIsNone(self.controller.advance_time(self.new_config.base_time))
        self.assertIs(self.controller.oper_config, self.old_config)

    def test_late_config_change_time_sample_is_rejected(self) -> None:
        self.controller.request_config_change(PtpTime(100, 0))
        late_now = PtpTime(100, 500_008)

        with self.assertRaisesRegex(
            RuntimeError, "ConfigChangeTime must be observed at exact timestamp equality"
        ):
            self.controller.next_cycle_start_time(late_now)
        with self.assertRaisesRegex(
            RuntimeError, "ConfigChangeTime must be observed at exact timestamp equality"
        ):
            self.controller.advance_time(late_now)

        self.assertTrue(self.controller.config_pending)
        self.assertIs(self.controller.oper_config, self.old_config)
        self.assertIs(self.controller.pending_config, self.new_config)

    def test_reenable_requires_a_new_request_after_pending_cancellation(self) -> None:
        self.controller.request_config_change(PtpTime(100, 0))
        self.controller.set_gate_enabled(False, PtpTime(100, 100))
        self.controller.set_gate_enabled(True, PtpTime(100, 600_000))

        self.assertFalse(self.controller.config_pending)
        self.assertIs(self.controller.oper_config, self.old_config)

        self.controller.request_config_change(PtpTime(100, 600_000))
        self.assertTrue(self.controller.config_pending)
        self.assertEqual(self.controller.config_change_time, PtpTime(100, 625_000))
        activation = self.controller.advance_time(PtpTime(100, 625_000))
        self.assertIsNotNone(activation)
        self.assertIs(self.controller.oper_config, self.new_config)

    def test_disabled_state_request_can_be_cancelled(self) -> None:
        controller = ConfigurationController(
            timebase=self.timebase,
            admin_config=self.new_config,
        )
        controller.request_config_change(PtpTime(100, 0))
        controller.cancel_latched_request()
        self.assertFalse(controller.config_change)
        self.assertFalse(controller.config_pending)
        self.assertIsNone(controller.pending_config)

    def test_cancel_is_not_allowed_after_request_is_accepted(self) -> None:
        self.controller.request_config_change(PtpTime(100, 0))
        with self.assertRaisesRegex(RuntimeError, "no unaccepted request"):
            self.controller.cancel_latched_request()

    def test_past_base_time_rolls_forward_and_increments_error_when_enabled(self) -> None:
        past_config = self.config(
            base_time=PtpTime(100, 0),
            cycle=CycleTime(1, 10_000),
            gate_states=0x22,
        )
        self.controller.set_admin_config(past_config)
        now = PtpTime(100, 250_000)
        self.controller.request_config_change(now)

        self.assertEqual(self.controller.config_change_error, 1)
        self.assertEqual(self.controller.config_change_time, PtpTime(100, 300_000))
        self.assertIsNone(self.controller.advance_time(PtpTime(100, 299_999)))
        activation = self.controller.advance_time(PtpTime(100, 300_000))
        self.assertIsNotNone(activation)
        self.assertEqual(activation.cycle_start_time, PtpTime(100, 300_000))
        self.assertIs(self.controller.oper_config, past_config)

    def test_past_base_time_error_counter_follows_gate_enabled_rule(self) -> None:
        controller = ConfigurationController(
            timebase=self.timebase,
            admin_config=self.old_config,
            oper_config=None,
            gate_enabled=False,
        )
        controller.request_config_change(PtpTime(100, 100_000))
        self.assertEqual(controller.config_change_error, 0)
        controller.set_gate_enabled(True, PtpTime(100, 200_000))
        self.assertEqual(controller.config_change_error, 1)
        self.assertTrue(controller.config_pending)
        activation_time = controller.config_change_time
        self.assertIsNotNone(activation_time)
        activation = controller.advance_time(activation_time)
        self.assertIsNotNone(activation)
        self.assertIsNone(activation.previous)
        self.assertEqual(activation.cycle_start_time, activation_time)

    def test_invalid_admin_replacement_does_not_change_admin_or_oper(self) -> None:
        coarse_timebase = Timebase(tick_granularity_x10_ns=80)
        coarse_schedule = validate_schedule(
            [GateControlEntry(GateOperation.SET_GATE_STATES, 0xFF, 8)],
            CycleTime(1, 8_000),
            coarse_timebase,
            supported_list_max=16,
        )
        invalid = ScheduleConfiguration(
            base_time=PtpTime(100, 0),
            schedule=coarse_schedule,
            cycle_time_extension_ns=1,
        )
        coarse_controller = ConfigurationController(
            timebase=coarse_timebase,
            admin_config=ScheduleConfiguration(
                base_time=PtpTime(100, 0),
                schedule=coarse_schedule,
                cycle_time_extension_ns=0,
            ),
        )
        original_admin = coarse_controller.admin_config
        original_oper = coarse_controller.oper_config
        with self.assertRaisesRegex(ScheduleValidationError, "CycleTimeExtension"):
            coarse_controller.set_admin_config(invalid)
        self.assertIs(coarse_controller.admin_config, original_admin)
        self.assertIs(coarse_controller.oper_config, original_oper)

    def test_cycle_timer_uses_old_schedule_during_pending_change(self) -> None:
        near_config = self.config(
            base_time=PtpTime(100, 80_000),
            cycle=CycleTime(1, 8_000),
            gate_states=0x0F,
        )
        self.controller.set_admin_config(near_config)
        self.controller.request_config_change(PtpTime(100, 0))
        # The 80 us change is inside the old 100 us cycle window.
        self.assertEqual(
            self.controller.next_cycle_start_time(PtpTime(100, 0)),
            near_config.base_time,
        )

    def test_cycle_timer_repeats_old_schedule_when_change_is_far_away(self) -> None:
        far_config = self.config(
            base_time=PtpTime(100, 500_000),
            cycle=CycleTime(1, 8_000),
            gate_states=0x0F,
            extension=0,
        )
        self.controller.set_admin_config(far_config)
        self.controller.request_config_change(PtpTime(100, 0))
        # Old cycle is 100 us; the 500 us change is farther than one cycle.
        self.assertEqual(
            self.controller.next_cycle_start_time(PtpTime(100, 1)),
            PtpTime(100, 100_000),
        )


    def test_cycle_start_query_does_not_advance_observed_current_time(self) -> None:
        future_sample = PtpTime(100, 1)
        self.assertEqual(
            self.controller.next_cycle_start_time(future_sample),
            PtpTime(100, 100_000),
        )
        # A pure Cycle Timer query must not make a management operation at the
        # controller's actual current sample appear to move backwards.
        self.controller.request_config_change(PtpTime(100, 0))
        self.assertTrue(self.controller.config_pending)

    def test_disabled_controller_has_no_cycle_start(self) -> None:
        self.controller.set_gate_enabled(False, PtpTime(100, 0))
        self.assertIsNone(self.controller.next_cycle_start_time(PtpTime(100, 0)))

    def test_backwards_or_off_grid_current_time_is_rejected(self) -> None:
        self.controller.advance_time(PtpTime(100, 8))
        with self.assertRaises(TimeConfigurationError):
            self.controller.advance_time(PtpTime(100, 7))

        coarse_timebase = Timebase(tick_granularity_x10_ns=80)
        coarse_schedule = validate_schedule(
            [GateControlEntry(GateOperation.SET_GATE_STATES, 0xFF, 8)],
            CycleTime(1, 8_000),
            coarse_timebase,
            supported_list_max=16,
        )
        coarse_controller = ConfigurationController(
            timebase=coarse_timebase,
            admin_config=ScheduleConfiguration(PtpTime(100, 0), coarse_schedule),
        )
        coarse_controller.advance_time(PtpTime(100, 8))
        with self.assertRaises(TimeConfigurationError):
            coarse_controller.advance_time(PtpTime(100, 9))


if __name__ == "__main__":
    unittest.main()
