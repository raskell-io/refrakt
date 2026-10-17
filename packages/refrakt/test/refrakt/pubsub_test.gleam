import gleam/erlang/process
import gleeunit/should
import refrakt/pubsub

pub fn broadcast_reaches_subscribers_test() {
  let assert Ok(ps) = pubsub.start()
  let inbox = process.new_subject()

  pubsub.subscribe(ps, "room:1", inbox)
  pubsub.broadcast(ps, "room:1", "hello")

  process.receive(inbox, 1000) |> should.equal(Ok("hello"))
}

pub fn unsubscribed_subject_receives_nothing_test() {
  let assert Ok(ps) = pubsub.start()
  let inbox = process.new_subject()

  pubsub.subscribe(ps, "room:1", inbox)
  pubsub.unsubscribe(ps, "room:1", inbox)
  pubsub.broadcast(ps, "room:1", "hello")

  process.receive(inbox, 100) |> should.equal(Error(Nil))
}
