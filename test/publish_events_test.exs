defmodule EventStore.PublishEventsTest do
  use EventStore.StorageCase

  alias EventStore.{EventFactory,Publisher,Subscriptions,Subscriber,Wait}
  alias EventStore.Subscriptions.Subscription

  @all_stream "$all"
  @subscription_name "test_subscription"

  test "should publish events ordered by event id" do
    stream1_uuid = UUID.uuid4()
    stream2_uuid = UUID.uuid4()
    stream3_uuid = UUID.uuid4()

    stream1_events = EventFactory.create_recorded_events(1, stream1_uuid, 1)
    stream2_events = EventFactory.create_recorded_events(1, stream2_uuid, 2)
    stream3_events = EventFactory.create_recorded_events(1, stream3_uuid, 3)

    {:ok, subscriber} = Subscriber.start_link(self())
    {:ok, subscription} = Subscriptions.subscribe_to_stream(@all_stream, @subscription_name, subscriber, start_from: :current)

    Wait.until(fn ->
      assert Registry.lookup(EventStore.Subscriptions.PubSub, @all_stream) !== []
    end)

    # notify stream2 events before stream3 and stream1 (out of order)
    Publisher.notify_events(stream2_uuid, stream2_events)
    Publisher.notify_events(stream3_uuid, stream3_events)
    Publisher.notify_events(stream1_uuid, stream1_events)

    # should receive events in correct order (by event_id)
    assert_receive {:events, stream1_received_events}
    Subscription.ack(subscription, stream1_received_events)

    assert_receive {:events, stream2_received_events}
    Subscription.ack(subscription, stream2_received_events)

    assert_receive {:events, stream3_received_events}
    Subscription.ack(subscription, stream3_received_events)

    assert stream1_received_events == EventFactory.deserialize_events(stream1_events)
    assert stream2_received_events == EventFactory.deserialize_events(stream2_events)
    assert stream3_received_events == EventFactory.deserialize_events(stream3_events)

    assert Subscriber.received_events(subscriber) == EventFactory.deserialize_events(stream1_events ++ stream2_events ++ stream3_events)
  end
end