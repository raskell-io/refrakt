# Tasks App Example

A task management app built with [Refrakt](https://github.com/raskell-io/refrakt) and SQLite.

## Features

- Tasks with title and completed flag
- Full CRUD (create, read, update, delete)
- SQLite database (no external server needed)

## Setup

```bash
# Install dependencies
gleam build

# Create the database and run migrations
sqlite3 tasks_app.db < src/tasks_app/data/migrations/001_create_tasks.sql

# Start the server
gleam run
# → http://localhost:4000
```

## Routes

```
GET     /               Home page
GET     /tasks          List all tasks
GET     /tasks/new      New task form
POST    /tasks          Create task
GET     /tasks/:id      Show task
GET     /tasks/:id/edit Edit task form
PUT     /tasks/:id      Update task
DELETE  /tasks/:id      Delete task
```
