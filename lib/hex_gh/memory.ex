defmodule HexGh.Memory do
  @moduledoc """
  Vector memory store backed by SQLite + sqlite-vec.

  Stores facts with their embeddings for semantic similarity search.
  The SQLite connection is kept open in GenServer state — since the GenServer
  serializes all access, this aligns with SQLite's single-writer model and
  avoids the overhead of reopening + reloading the sqlite-vec extension per call.

  ## sqlite-vec storage model

  sqlite-vec uses a `vec0` virtual table as the vector index/store, but vectors
  are passed in and out as **raw binary blobs** (little-endian float32 arrays).
  The `vec0` table handles both persistence and KNN indexing internally.
  KNN queries use `WHERE embedding MATCH ?blob AND k = ?limit` syntax
  (not standard SQL `LIMIT`).
  """
  use GenServer

  alias Exqlite.Basic

  defp vec_dimensions, do: Application.get_env(:hex_gh, :mistral_embed_dimensions, 1024)

  # Client API

  def start_link(opts \\ []) do
    db_path =
      Keyword.get(opts, :db_path, Application.get_env(:hex_gh, :memory_db_path, "priv/memory.db"))

    GenServer.start_link(__MODULE__, db_path, name: __MODULE__)
  end

  def save_fact(category, content, embedding) when is_list(embedding) do
    GenServer.call(__MODULE__, {:save_fact, category, content, embedding})
  end

  def search_relevant(query_embedding, limit \\ 5) when is_list(query_embedding) do
    GenServer.call(__MODULE__, {:search_relevant, query_embedding, limit})
  end

  # Server callbacks

  @impl true
  def init(db_path) do
    File.mkdir_p!(Path.dirname(db_path))

    case init_db(db_path) do
      {:ok, conn} -> {:ok, %{conn: conn}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:save_fact, category, content, embedding}, _from, state) do
    blob = embedding_to_blob(embedding)

    result =
      with {:ok, _, _, conn} <-
             Basic.exec(state.conn, "INSERT INTO memories (category, content) VALUES (?, ?)", [
               category,
               content
             ]),
           {:ok, rows, _cols} <-
             Basic.rows(Basic.exec(conn, "SELECT last_insert_rowid()", [])) do
        [[row_id]] = rows

        case Basic.exec(conn, "INSERT INTO memory_vectors (rowid, embedding) VALUES (?, ?)", [
               row_id,
               {:blob, blob}
             ]) do
          {:ok, _, _, updated_conn} ->
            {:ok, row_id, updated_conn}

          {:error, err, conn} ->
            {:error, err, conn}
        end
      end

    case result do
      {:ok, row_id, conn} ->
        {:reply, {:ok, row_id}, %{state | conn: conn}}

      {:error, reason, conn} ->
        {:reply, {:error, reason}, %{state | conn: conn}}
    end
  end

  @impl true
  def handle_call({:search_relevant, query_embedding, limit}, _from, state) do
    blob = embedding_to_blob(query_embedding)

    result =
      Basic.exec(
        state.conn,
        """
        SELECT m.id, m.category, m.content, v.distance
        FROM memory_vectors v
        JOIN memories m ON m.id = v.rowid
        WHERE v.embedding MATCH ? AND k = ?
        ORDER BY v.distance
        """,
        [{:blob, blob}, limit]
      )
      |> dbg()

    case Basic.rows(result) do
      {:ok, rows, _cols} ->
        results =
          Enum.map(rows, fn [id, category, content, distance] ->
            %{id: id, category: category, content: content, distance: distance}
          end)

        {:reply, {:ok, results}, update_conn(state, result)}

      {:error, reason} ->
        {:reply, {:error, reason}, update_conn(state, result)}
    end
  end

  # Private

  defp init_db(db_path) do
    with {:ok, conn} <- Basic.open(db_path),
         :ok <- Basic.enable_load_extension(conn),
         {:ok, _, _, conn} <- Basic.load_extension(conn, sqlite_vec_path()),
         {:ok, _, _, conn} <-
           Basic.exec(conn, """
           CREATE TABLE IF NOT EXISTS memories (
             id INTEGER PRIMARY KEY AUTOINCREMENT,
             category TEXT NOT NULL,
             content TEXT NOT NULL,
             created_at DATETIME DEFAULT CURRENT_TIMESTAMP
           )
           """),
         {:ok, _, _, conn} <-
           Basic.exec(conn, """
           CREATE VIRTUAL TABLE IF NOT EXISTS memory_vectors USING vec0(
             embedding float[#{vec_dimensions()}]
           )
           """) do
      {:ok, conn}
    end
  end

  defp sqlite_vec_path do
    case Application.get_env(:hex_gh, :sqlite_vec_path) do
      path when is_binary(path) and path != "" ->
        path

      _ ->
        case System.cmd("python3", ["-c", "import sqlite_vec; print(sqlite_vec.loadable_path())"],
               stderr_to_stdout: true
             ) do
          {path, 0} ->
            String.trim(path)

          _ ->
            raise "sqlite-vec not found. Set SQLITE_VEC_PATH or install: pip3 install sqlite-vec"
        end
    end
  end

  defp embedding_to_blob(embedding) do
    embedding
    |> Enum.map(&<<&1::float-32-little>>)
    |> IO.iodata_to_binary()
  end

  defp update_conn(state, {:ok, _, _, conn}), do: %{state | conn: conn}
  defp update_conn(state, {:error, _, conn}), do: %{state | conn: conn}
end
