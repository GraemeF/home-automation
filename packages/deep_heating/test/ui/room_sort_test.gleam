import deep_heating/ui/room_sort.{sort_by_temperature}
import gleam/list
import gleeunit/should
import ui/test_helpers.{room_with_temp, room_without_temp}

pub fn sorts_hottest_first_test() {
  let rooms = [
    room_with_temp("Cold", 18.0),
    room_with_temp("Hot", 24.0),
    room_with_temp("Medium", 21.0),
  ]

  let sorted = sort_by_temperature(rooms)
  let names = list.map(sorted, fn(r) { r.name })

  names |> should.equal(["Hot", "Medium", "Cold"])
}

pub fn rooms_without_temp_sort_to_end_test() {
  let rooms = [room_without_temp("Unknown"), room_with_temp("Known", 20.0)]

  let sorted = sort_by_temperature(rooms)
  let names = list.map(sorted, fn(r) { r.name })

  names |> should.equal(["Known", "Unknown"])
}

pub fn empty_list_returns_empty_test() {
  sort_by_temperature([]) |> should.equal([])
}

pub fn single_room_returns_same_test() {
  let rooms = [room_with_temp("Only", 20.0)]
  let sorted = sort_by_temperature(rooms)

  let assert [room] = sorted
  room.name |> should.equal("Only")
}

pub fn rooms_with_same_temp_are_stable_test() {
  let rooms = [
    room_with_temp("First", 20.0),
    room_with_temp("Second", 20.0),
    room_with_temp("Third", 20.0),
  ]

  let sorted = sort_by_temperature(rooms)
  let names = list.map(sorted, fn(r) { r.name })

  // Same temps should maintain original order (stable sort)
  names |> should.equal(["First", "Second", "Third"])
}
