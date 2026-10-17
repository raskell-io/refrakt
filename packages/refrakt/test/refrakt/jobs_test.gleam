import gleam/erlang/process
import gleeunit/should
import refrakt/jobs

pub fn queued_jobs_all_run_with_concurrency_one_test() {
  let assert Ok(runner) = jobs.start(max_concurrency: 1)
  let done = process.new_subject()

  jobs.enqueue(runner, fn() { process.send(done, 1) })
  jobs.enqueue(runner, fn() { process.send(done, 2) })
  jobs.enqueue(runner, fn() { process.send(done, 3) })

  process.receive(done, 1000) |> should.equal(Ok(1))
  process.receive(done, 1000) |> should.equal(Ok(2))
  process.receive(done, 1000) |> should.equal(Ok(3))
}

pub fn crashing_job_does_not_stop_runner_test() {
  let assert Ok(runner) = jobs.start(max_concurrency: 1)
  let done = process.new_subject()

  jobs.enqueue_named(runner, "boom", fn() { panic as "job failed" })
  jobs.enqueue(runner, fn() { process.send(done, Nil) })

  process.receive(done, 1000) |> should.equal(Ok(Nil))
}
