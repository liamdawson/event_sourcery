class TestPoller
  attr_accessor :times, :after_poll_callback

  def initialize(times: 1, after_poll_callback: proc { })
    @times = times
    @after_poll_callback = after_poll_callback
  end

  def poll(*args, &block)
    Array(1..times).each do
      yield
      after_poll_callback.call
    end
  end
end

RSpec.describe EventSourcery::EventStore::Subscription do
  def on_new_events_callback(events)
    @event_batches << events
  end

  let(:event_types) { nil }
  let(:event_store) { EventSourcery::Memory::EventStore.new }
  subject(:subscription) { described_class.new(event_store: event_store,
                                               poll_waiter: waiter,
                                               event_types: event_types,
                                               from_event_id: 1,
                                               subscription_master: subscription_master,
                                               on_new_events: method(:on_new_events_callback)) }

  let(:waiter) { TestPoller.new }
  let(:subscription_master) { spy(EventSourcery::EventStore::SignalHandlingSubscriptionMaster) }

  before do
    @event_batches = []
  end

  it 'yields new events' do
    event_store.sink(ItemAdded.new(aggregate_id: SecureRandom.uuid))
    subscription.start
    expect(@event_batches.first.map(&:id)).to eq [1]
  end

  it 'yields new events in batches' do
    waiter.times = 2
    waiter.after_poll_callback = proc { event_store.sink(ItemAdded.new(aggregate_id: SecureRandom.uuid)) }
    event_store.sink(ItemAdded.new(aggregate_id: SecureRandom.uuid))
    event_store.sink(ItemAdded.new(aggregate_id: SecureRandom.uuid))
    subscription.start
    expect(@event_batches.first.map(&:id)).to eq [1, 2]
  end

  it 'marks a safe point to shutdown' do
    subscription.start
    expect(subscription_master).to have_received(:shutdown_if_requested)
  end

  context 'with event types' do
    let(:event_types) { ['item_added', 'item_removed'] }

    it 'filters by the given event type' do
      event_store.sink(ItemAdded.new(aggregate_id: SecureRandom.uuid))
      event_store.sink(ItemRemoved.new(aggregate_id: SecureRandom.uuid))
      event_store.sink(TermsAccepted.new(aggregate_id: SecureRandom.uuid))
      waiter.times = 2
      waiter.after_poll_callback = proc { event_store.sink(ItemAdded.new(aggregate_id: SecureRandom.uuid)) }
      subscription.start
      expect(@event_batches.count).to eq 2
      expect(@event_batches.first.map(&:type)).to eq ['item_added', 'item_removed']
      expect(@event_batches.last.map(&:type)).to eq ['item_added']
    end
  end

  it 'uses a default batch size' do
    expect(event_store).to receive(:get_next_from).with(1, event_types: nil, limit: 1000).and_return []

    subscription.start
  end

  it 'allows specifying a batch size' do
    subscription = described_class.new(event_store: event_store,
                                       poll_waiter: waiter,
                                       event_types: event_types,
                                       from_event_id: 1,
                                       subscription_master: subscription_master,
                                       on_new_events: method(:on_new_events_callback),
                                       batch_size: 42)

    expect(event_store).to receive(:get_next_from).with(1, event_types: nil, limit: 42).and_return []

    subscription.start
  end
end
