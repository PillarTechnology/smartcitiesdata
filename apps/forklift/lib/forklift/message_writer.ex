defmodule Forklift.MessageWriter do
  @moduledoc false
  alias Forklift.{RedisClient, PrestoClient}
  alias SCOS.DataMessage
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_args) do
    schedule_work()
    {:ok, %{}}
  end

  def handle_info(:work, state) do
    RedisClient.read_all_batched_messages()
    |> Enum.map(&parse_data_message/1)
    |> Enum.filter(&(&1 != :parsing_error))
    |> Enum.group_by(&extract_dataset_id/1)
    |> Enum.map(&start_upload_and_delete_task/1)
    |> Enum.each(&Task.await/1)

    schedule_work()
    {:noreply, state}
  end

  defp start_upload_and_delete_task({dataset_id, key_message_pairs}) do
    Task.Supervisor.async_nolink(Forklift.TaskSupervisor, fn ->
      redis_keys = Enum.map(key_message_pairs, fn {redis_key, msg} -> redis_key end)
      messages = Enum.map(key_message_pairs, fn {redis_key, msg} -> msg end)

      PrestoClient.upload_data(dataset_id, messages)
      RedisClient.delete(redis_keys)
    end)
  end

  defp extract_dataset_id({key, _}) do
    key |> String.split(":") |> Enum.at(2)
  end

  defp parse_data_message({key, message}) do
    case DataMessage.new(message) do
      {:ok, value} ->
        {key, value}

      _ ->
        send_to_dead_letter_queue(message)
        :parsing_error
    end
  end

  defp send_to_dead_letter_queue(message) do
    nil
  end

  defp schedule_work do
    Process.send_after(self(), :work, 60_000)
  end
end
