# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventDescriptionSection, type: :model do
  subject(:section) { build(:event_description_section) }

  it { is_expected.to belong_to(:event) }
  it { is_expected.to have_many(:event_description_section_translations).dependent(:destroy) }

  describe '#label_for and #content_for' do
    let!(:section) { create(:event_description_section) }

    before do
      Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
      Language.find_or_create_by!(code: 'en-US') { |l| l.name = 'English' }
      EventDescriptionSectionTranslation.create!(
        event_description_section: section, languages_code: 'ro-RO',
        label: 'Program', content: '<p>Detalii program</p>'
      )
      EventDescriptionSectionTranslation.create!(
        event_description_section: section, languages_code: 'en-US',
        label: 'Schedule', content: '<p>Schedule details</p>'
      )
    end

    it 'returns label for an exact language match' do
      expect(section.label_for('en-US')).to eq('Schedule')
    end

    it 'returns content for an exact language match' do
      expect(section.content_for('en-US')).to eq('<p>Schedule details</p>')
    end

    it 'falls back to ro-RO when the requested language has no translation' do
      expect(section.label_for('fr-FR')).to eq('Program')
    end
  end
end
