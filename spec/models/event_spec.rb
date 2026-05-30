# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Event do
  let(:event) { create(:event, max_number_of_people: 2) }

  it 'has a valid factory' do
    expect(build(:event)).to be_valid
  end

  describe 'ActiveModel validations' do
    context 'when max number is reached' do
      before do
        create_list(:attendee, 2, event: event)
      end

      it 'returns fully booked' do
        expect(event.fully_booked?).to be true
      end
    end

    context 'when max number is not reached' do
      before do
        create_list(:attendee, 1, event: event)
      end

      it 'returns event not fully booked' do
        expect(event.fully_booked?).to be false
      end
    end
  end

  describe '.by_filter' do
    let!(:upcoming_event) { create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now) }
    let!(:past_event)     { create(:event, status: :live, start_date: 5.days.ago,      end_date: 2.days.ago) }
    let!(:draft_event)    { create(:event, status: :draft, start_date: 5.days.from_now, end_date: 8.days.from_now) }

    it 'upcoming returns only future live events' do
      result = described_class.by_filter('upcoming')
      expect(result).to include(upcoming_event)
      expect(result).not_to include(past_event, draft_event)
    end

    it 'past returns only past live events' do
      result = described_class.by_filter('past')
      expect(result).to include(past_event)
      expect(result).not_to include(upcoming_event, draft_event)
    end

    it 'all returns all live events regardless of date' do
      result = described_class.by_filter('all')
      expect(result).to include(upcoming_event, past_event)
      expect(result).not_to include(draft_event)
    end

    it 'unknown filter falls back to all live events' do
      result = described_class.by_filter('garbage')
      expect(result).to include(upcoming_event, past_event)
      expect(result).not_to include(draft_event)
    end
  end

  describe '.by_keyword' do
    before { Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' } }

    let!(:event_a) do
      e = create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now)
      create(:events_translation, event: e, languages_code: 'ro-RO', name: 'Conferinta anuala', tag_line: 'O intalnire')
      e
    end
    let!(:event_b) do
      e = create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now)
      create(:events_translation, event: e, languages_code: 'ro-RO', name: 'Tabara copii', tag_line: 'Multa distractie')
      e
    end

    it 'matches by name' do
      expect(described_class.by_keyword('conferinta', 'ro-RO')).to include(event_a)
      expect(described_class.by_keyword('conferinta', 'ro-RO')).not_to include(event_b)
    end

    it 'matches by tag_line' do
      expect(described_class.by_keyword('distractie', 'ro-RO')).to include(event_b)
      expect(described_class.by_keyword('distractie', 'ro-RO')).not_to include(event_a)
    end

    it 'is case-insensitive' do
      expect(described_class.by_keyword('TABARA', 'ro-RO')).to include(event_b)
    end

    it 'returns all events when search is blank' do
      expect(described_class.by_keyword('', 'ro-RO')).to include(event_a, event_b)
    end

    it 'returns all events when search is nil' do
      expect(described_class.by_keyword(nil, 'ro-RO')).to include(event_a, event_b)
    end
  end

  describe '.by_year' do
    let!(:event_in_current_year) do
      create(:event, status: :live, start_date: Time.zone.parse('2026-06-01 10:00'),
                     end_date: Time.zone.parse('2026-06-04 18:00'))
    end
    let!(:event_in_prior_year) do
      create(:event, status: :live, start_date: Time.zone.parse('2025-03-01 10:00'),
                     end_date: Time.zone.parse('2025-03-04 18:00'))
    end

    it 'returns only events in the given year' do
      expect(described_class.by_year(2026)).to include(event_in_current_year)
      expect(described_class.by_year(2026)).not_to include(event_in_prior_year)
    end

    it 'returns all events when year is nil' do
      expect(described_class.by_year(nil)).to include(event_in_current_year, event_in_prior_year)
    end

    it 'returns all events when year is blank string' do
      expect(described_class.by_year('')).to include(event_in_current_year, event_in_prior_year)
    end
  end

  describe '.by_pricing' do
    let!(:free_event)      { create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now) }
    let!(:paid_event)      { create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now) }
    let!(:no_ticket_event) { create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now) }

    before do
      create(:ticket, event: free_event, price: 0)
      create(:ticket, event: paid_event, price: 150)
    end

    it 'free returns events with zero-price tickets' do
      expect(described_class.by_pricing('free')).to include(free_event)
      expect(described_class.by_pricing('free')).not_to include(paid_event)
    end

    it 'free returns events with no tickets at all' do
      expect(described_class.by_pricing('free')).to include(no_ticket_event)
    end

    it 'paid returns events with priced tickets only' do
      expect(described_class.by_pricing('paid')).to include(paid_event)
      expect(described_class.by_pricing('paid')).not_to include(free_event, no_ticket_event)
    end

    it 'both returns all events regardless of pricing' do
      expect(described_class.by_pricing('both')).to include(free_event, paid_event, no_ticket_event)
    end

    it 'nil / blank returns all events' do
      expect(described_class.by_pricing(nil)).to include(free_event, paid_event, no_ticket_event)
    end
  end

  describe '.sorted_for' do
    let!(:event_near) { create(:event, start_date: 2.days.from_now, end_date: 5.days.from_now) }
    let!(:event_far)  { create(:event, start_date: 30.days.from_now, end_date: 33.days.from_now) }

    it 'upcoming sorts start_date ascending (nearest first)' do
      result = described_class.sorted_for('upcoming').where(id: [event_near.id, event_far.id])
      expect(result.first).to eq(event_near)
    end

    it 'past sorts start_date descending (most recent first)' do
      result = described_class.sorted_for('past').where(id: [event_near.id, event_far.id])
      expect(result.first).to eq(event_far)
    end

    it 'all sorts start_date descending' do
      result = described_class.sorted_for('all').where(id: [event_near.id, event_far.id])
      expect(result.first).to eq(event_far)
    end
  end
end
