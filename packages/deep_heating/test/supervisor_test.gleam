import deep_heating/actor/ha_poller_actor
import deep_heating/actor/room_actor
import deep_heating/entity_id
import deep_heating/home_assistant
import deep_heating/home_config.{type HomeConfig, HomeConfig, RoomConfig}
import deep_heating/rooms_supervisor
import deep_heating/schedule
import deep_heating/supervisor
import deep_heating/temperature
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleeunit/should

// Supervisor startup tests

pub fn supervisor_starts_successfully_test() {
  // The top-level supervisor should start and return Ok with a Started record
  let result = supervisor.start()
  should.be_ok(result)
}

pub fn supervisor_returns_valid_pid_test() {
  // The started supervisor should have a valid PID
  let assert Ok(started) = supervisor.start()
  // Verify the PID is alive
  process.is_alive(started.pid) |> should.be_true
}

// Child supervisor tests

pub fn supervisor_has_house_mode_actor_test() {
  // The supervisor should have started a HouseModeActor child
  let assert Ok(started) = supervisor.start()

  // Get the house mode actor from the supervisor
  let result = supervisor.get_house_mode_actor(started.data)
  should.be_ok(result)
}

pub fn supervisor_has_state_aggregator_actor_test() {
  // The supervisor should have started a StateAggregatorActor child
  let assert Ok(started) = supervisor.start()

  // Get the state aggregator from the supervisor
  let result = supervisor.get_state_aggregator(started.data)
  should.be_ok(result)
}

pub fn house_mode_actor_is_alive_test() {
  // The house mode actor should be running
  let assert Ok(started) = supervisor.start()
  let assert Ok(house_mode) = supervisor.get_house_mode_actor(started.data)
  process.is_alive(house_mode.pid) |> should.be_true
}

pub fn state_aggregator_actor_is_alive_test() {
  // The state aggregator actor should be running
  let assert Ok(started) = supervisor.start()
  let assert Ok(aggregator) = supervisor.get_state_aggregator(started.data)
  process.is_alive(aggregator.pid) |> should.be_true
}

// Restart behaviour tests

pub fn supervisor_restarts_crashed_house_mode_actor_test() {
  // When the house mode actor crashes, the supervisor should restart it
  let assert Ok(started) = supervisor.start()

  // Get the house mode actor's PID
  let assert Ok(house_mode) = supervisor.get_house_mode_actor(started.data)
  let original_pid = house_mode.pid

  // Verify it's alive
  process.is_alive(original_pid) |> should.be_true

  // Crash the actor by sending an abnormal exit signal
  process.send_abnormal_exit(original_pid, "test_crash")

  // Give supervisor time to restart the child
  process.sleep(100)

  // The original PID should be dead
  process.is_alive(original_pid) |> should.be_false

  // Get the house mode actor again - should be a new process
  let assert Ok(new_house_mode) = supervisor.get_house_mode_actor(started.data)

  // The new actor should be alive
  process.is_alive(new_house_mode.pid) |> should.be_true

  // The new PID should be different from the original
  should.not_equal(new_house_mode.pid, original_pid)
}

pub fn supervisor_restarts_crashed_state_aggregator_test() {
  // When the state aggregator crashes, the supervisor should restart it
  let assert Ok(started) = supervisor.start()

  // Get the aggregator's PID
  let assert Ok(aggregator) = supervisor.get_state_aggregator(started.data)
  let original_pid = aggregator.pid

  // Crash the actor
  process.send_abnormal_exit(original_pid, "test_crash")

  // Give supervisor time to restart
  process.sleep(100)

  // Get the aggregator again
  let assert Ok(new_aggregator) = supervisor.get_state_aggregator(started.data)

  // Should be alive with a new PID
  process.is_alive(new_aggregator.pid) |> should.be_true
  should.not_equal(new_aggregator.pid, original_pid)
}

// =============================================================================
// HaPollerActor tests
// =============================================================================

fn create_test_poller_config() -> ha_poller_actor.PollerConfig {
  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")
  ha_poller_actor.PollerConfig(
    poll_interval_ms: 5000,
    heating_entity_id: heating_id,
    sleep_button_entity_id: "input_button.goodnight",
    managed_trv_ids: set.new(),
  )
}

pub fn supervisor_has_ha_poller_actor_test() {
  // When started with config, supervisor should have HaPollerActor child
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let poller_config = create_test_poller_config()

  let assert Ok(started) =
    supervisor.start_with_config(supervisor.SupervisorConfig(
      ha_client: ha_client,
      poller_config: poller_config,
      adjustments_path: option.None,
    ))

  // Get the ha poller actor from the supervisor
  let result = supervisor.get_ha_poller(started.data)
  should.be_ok(result)
}

pub fn ha_poller_actor_is_alive_test() {
  // The HaPollerActor should be running
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let poller_config = create_test_poller_config()

  let assert Ok(started) =
    supervisor.start_with_config(supervisor.SupervisorConfig(
      ha_client: ha_client,
      poller_config: poller_config,
      adjustments_path: option.None,
    ))

  let assert Ok(ha_poller) = supervisor.get_ha_poller(started.data)
  process.is_alive(ha_poller.pid) |> should.be_true
}

pub fn supervisor_restarts_crashed_ha_poller_actor_test() {
  // When the HaPollerActor crashes, the supervisor should restart it
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let poller_config = create_test_poller_config()

  let assert Ok(started) =
    supervisor.start_with_config(supervisor.SupervisorConfig(
      ha_client: ha_client,
      poller_config: poller_config,
      adjustments_path: option.None,
    ))

  // Get the HaPollerActor's PID
  let assert Ok(ha_poller) = supervisor.get_ha_poller(started.data)
  let original_pid = ha_poller.pid

  // Verify it's alive
  process.is_alive(original_pid) |> should.be_true

  // Crash the actor by sending an abnormal exit signal
  process.send_abnormal_exit(original_pid, "test_crash")

  // Give supervisor time to restart the child
  process.sleep(100)

  // The original PID should be dead
  process.is_alive(original_pid) |> should.be_false

  // Get the HaPollerActor again - should be a new process
  let assert Ok(new_ha_poller) = supervisor.get_ha_poller(started.data)

  // The new actor should be alive
  process.is_alive(new_ha_poller.pid) |> should.be_true

  // The new PID should be different from the original
  should.not_equal(new_ha_poller.pid, original_pid)
}

// =============================================================================
// RoomsSupervisor wiring tests
// =============================================================================

fn make_test_schedule() -> schedule.WeekSchedule {
  // Simple schedule: 20°C all day every day
  let assert Ok(time) = schedule.time_of_day(0, 0)
  let entry =
    schedule.ScheduleEntry(
      start: time,
      target_temperature: temperature.temperature(20.0),
    )
  let day = [entry]
  schedule.WeekSchedule(
    monday: day,
    tuesday: day,
    wednesday: day,
    thursday: day,
    friday: day,
    saturday: day,
    sunday: day,
  )
}

fn make_test_home_config() -> HomeConfig {
  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let assert Ok(sensor_id) = entity_id.sensor_entity_id("sensor.lounge_temp")
  let assert Ok(sleep_switch) =
    entity_id.goodnight_entity_id("input_button.goodnight")
  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.heating")

  HomeConfig(
    rooms: [
      RoomConfig(
        name: "lounge",
        temperature_sensor_entity_id: Some(sensor_id),
        climate_entity_ids: [trv_id],
        schedule: Some(make_test_schedule()),
      ),
    ],
    sleep_switch_id: sleep_switch,
    heating_id: heating_id,
  )
}

pub fn supervisor_starts_rooms_with_home_config_test() {
  // When started with config including HomeConfig, rooms should be created
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()

  let assert Ok(started) =
    supervisor.start_with_home_config(supervisor.SupervisorConfigWithRooms(
      ha_client: ha_client,
      poller_config: poller_config,
      adjustments_path: None,
      home_config: home_config,
    ))

  // Get the rooms supervisor from the main supervisor
  let assert Ok(rooms_sup) = supervisor.get_rooms_supervisor(started.data)

  // Should have one room
  let room_supervisors = rooms_supervisor.get_room_supervisors(rooms_sup)
  list.length(room_supervisors) |> should.equal(1)
}

pub fn supervisor_rooms_are_accessible_by_name_test() {
  // Rooms should be accessible by name through the supervisor
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()

  let assert Ok(started) =
    supervisor.start_with_home_config(supervisor.SupervisorConfigWithRooms(
      ha_client: ha_client,
      poller_config: poller_config,
      adjustments_path: None,
      home_config: home_config,
    ))

  // Get the rooms supervisor
  let assert Ok(rooms_sup) = supervisor.get_rooms_supervisor(started.data)

  // Should be able to get room by name
  let lounge_result = rooms_supervisor.get_room_by_name(rooms_sup, "lounge")
  should.be_ok(lounge_result)
}

pub fn supervisor_room_actors_are_alive_test() {
  // Room actors started by the supervisor should be alive and responding
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()

  let assert Ok(started) =
    supervisor.start_with_home_config(supervisor.SupervisorConfigWithRooms(
      ha_client: ha_client,
      poller_config: poller_config,
      adjustments_path: None,
      home_config: home_config,
    ))

  // Get the rooms supervisor and lounge room
  let assert Ok(rooms_sup) = supervisor.get_rooms_supervisor(started.data)
  let assert Ok(lounge) = rooms_supervisor.get_room_by_name(rooms_sup, "lounge")

  // Get the room actor and query its state
  let assert Ok(room_actor_ref) = rooms_supervisor.get_room_actor(lounge)
  let reply = process.new_subject()
  process.send(room_actor_ref.subject, room_actor.GetState(reply))

  // Should respond with state showing the room name
  let assert Ok(state) = process.receive(reply, 1000)
  state.name |> should.equal("lounge")
}
