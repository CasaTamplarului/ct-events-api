# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventBooleanField, type: :model do
  subject(:field) { build(:event_boolean_field) }

  it { is_expected.to belong_to(:event) }
  it { is_expected.to have_many(:event_boolean_field_translations).dependent(:destroy) }
  it { is_expected.to validate_inclusion_of(:display_as).in_array(%w[toggle checkbox]) }

  describe '#label_for' do
    let!(:field) { create(:event_boolean_field) }

    before do
      Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
      Language.find_or_create_by!(code: 'en-US') { |l| l.name = 'English' }
      EventBooleanFieldTranslation.create!(event_boolean_field: field, languages_code: 'ro-RO',
                                           label: 'Întrebare', true_label: 'Da', false_label: 'Nu')
      EventBooleanFieldTranslation.create!(event_boolean_field: field, languages_code: 'en-US',
                                           label: 'Question', true_label: 'Yes', false_label: 'No')
    end

    it 'returns the label for an exact language match' do
      expect(field.label_for('en-US')).to eq('Question')
    end

    it 'falls back to ro-RO when the requested language has no translation' do
      expect(field.label_for('fr-FR')).to eq('Întrebare')
    end
  end

  describe '#true_label_for and #false_label_for' do
    let!(:field) { create(:event_boolean_field) }

    before do
      Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
      EventBooleanFieldTranslation.create!(event_boolean_field: field, languages_code: 'ro-RO',
                                           label: 'Întrebare', true_label: 'Da, accept', false_label: 'Nu accept')
    end

    it 'returns true_label for the language' do
      expect(field.true_label_for('ro-RO')).to eq('Da, accept')
    end

    it 'returns false_label for the language' do
      expect(field.false_label_for('ro-RO')).to eq('Nu accept')
    end
  end
end
