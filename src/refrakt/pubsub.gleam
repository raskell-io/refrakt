/// Topic-based publish/subscribe for real-time messaging.
///
/// Uses ETS for subscriber tracking and OTP processes for message dispatch.
///
/// ## Usage
///
/// ```gleam
/// // Start the PubSub system
/// let assert Ok(ps) = pubsub.start()
///
/// // Subscribe to a topic
/// let subject = process.new_subject()
/// pubsub.subscribe(ps, "chat:lobby", subject)
///
/// // Publish a message
/// pubsub.broadcast(ps, "chat:lobby", "Hello everyone!")
///
/// // All subscribers on "chat:lobby" receive the message
/// let assert Ok(msg) = process.receive(subject, 1000)
/// // msg == "Hello everyone!"
/// ```
///
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result

/// A running PubSub instance.
pub type PubSub(msg) =
  Subject(PubSubMessage(msg))

/// Messages the PubSub actor handles.
pub opaque type PubSubMessage(msg) {
  Subscribe(topic: String, subscriber: Subject(msg))
  Unsubscribe(topic: String, subscriber: Subject(msg))
  Broadcast(topic: String, message: msg)
  GetSubscribers(topic: String, reply: Subject(List(Subject(msg))))
}

type State(msg) {
  State(topics: Dict(String, List(Subject(msg))))
}

/// Start a new PubSub actor.
pub fn start() -> Result(PubSub(msg), actor.StartError) {
  actor.new(State(topics: dict.new()))
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.subject })
}

/// Subscribe a subject to a topic.
pub fn subscribe(ps: PubSub(msg), topic: String, subscriber: Subject(msg)) {
  actor.send(ps, Subscribe(topic:, subscriber:))
}

/// Unsubscribe a subject from a topic.
pub fn unsubscribe(ps: PubSub(msg), topic: String, subscriber: Subject(msg)) {
  actor.send(ps, Unsubscribe(topic:, subscriber:))
}

/// Broadcast a message to all subscribers of a topic.
pub fn broadcast(ps: PubSub(msg), topic: String, message: msg) {
  actor.send(ps, Broadcast(topic:, message:))
}

fn handle_message(
  msg: PubSubMessage(msg),
  state: State(msg),
) -> actor.Next(PubSubMessage(msg), State(msg)) {
  case msg {
    Subscribe(topic:, subscriber:) -> {
      let subs = case dict.get(state.topics, topic) {
        Ok(existing) -> [subscriber, ..existing]
        Error(_) -> [subscriber]
      }
      actor.continue(State(topics: dict.insert(state.topics, topic, subs)))
    }

    Unsubscribe(topic:, subscriber:) -> {
      let topics = case dict.get(state.topics, topic) {
        Ok(existing) -> {
          let filtered = list.filter(existing, fn(s) { s != subscriber })
          dict.insert(state.topics, topic, filtered)
        }
        Error(_) -> state.topics
      }
      actor.continue(State(topics:))
    }

    Broadcast(topic:, message:) -> {
      case dict.get(state.topics, topic) {
        Ok(subscribers) ->
          list.each(subscribers, fn(sub) { process.send(sub, message) })
        Error(_) -> Nil
      }
      actor.continue(state)
    }

    GetSubscribers(topic:, reply:) -> {
      let subs = case dict.get(state.topics, topic) {
        Ok(s) -> s
        Error(_) -> []
      }
      process.send(reply, subs)
      actor.continue(state)
    }
  }
}
