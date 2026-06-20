# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QaSession do
  let(:admin)   { create(:user, role: 'admin') }
  let(:event)   { create(:event) }

  describe 'code auto-generation' do
    it 'generates an 8-character alphanumeric code before create' do
      session = QaSession.create!(event: event, created_by_user: admin)
      expect(session.code).to match(/\A[A-Z0-9]{8}\z/)
    end

    it 'does not overwrite a manually set code on create' do
      session = QaSession.new(event: event, created_by_user: admin)
      session.code = 'MYCODE01'
      session.save!
      expect(session.reload.code).to eq('MYCODE01')
    end
  end

  describe '#name_for' do
    let!(:language_ro) { Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' } }
    let!(:language_en) { Language.find_or_create_by!(code: 'en-US') { |l| l.name = 'English' } }
    let(:session) { create(:qa_session, event: event, created_by_user: admin) }

    before do
      session.qa_session_translations.create!(languages_code: 'ro-RO', name: 'Sesiunea 1')
      session.qa_session_translations.create!(languages_code: 'en-US', name: 'Session 1')
    end

    it 'returns the name for the requested language' do
      expect(session.name_for('ro-RO')).to eq('Sesiunea 1')
      expect(session.name_for('en-US')).to eq('Session 1')
    end

    it 'falls back to the first available translation when language not found' do
      expect(session.name_for('fr-FR')).to eq('Sesiunea 1')
    end
  end

  describe 'enum status' do
    it 'defaults to open' do
      session = QaSession.create!(event: event, created_by_user: admin)
      expect(session).to be_open
    end

    it 'can be closed' do
      session = create(:qa_session, event: event, created_by_user: admin)
      session.closed!
      expect(session.reload).to be_closed
    end
  end
end
