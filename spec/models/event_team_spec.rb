# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventTeam, type: :model do
  let(:event) { create(:event) }

  it 'is valid with only a name' do
    expect(build(:event_team, event: event, name: 'Red', icon: nil, colour: nil)).to be_valid
  end

  it 'is valid with only an icon' do
    expect(build(:event_team, event: event, name: nil, icon: '🔥', colour: nil)).to be_valid
  end

  it 'is valid with only a colour' do
    expect(build(:event_team, event: event, name: nil, icon: nil, colour: '#FF5733')).to be_valid
  end

  it 'is invalid when all fields are blank' do
    team = build(:event_team, event: event, name: nil, icon: nil, colour: nil)
    expect(team).not_to be_valid
    expect(team.errors[:base]).to include('At least one of name, icon, or colour must be present')
  end

  it 'defaults score to 0' do
    team = create(:event_team, event: event, name: 'Red')
    expect(team.score).to eq(0)
  end
end
