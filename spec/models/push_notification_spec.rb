# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PushNotification, type: :model do
  let(:admin) { create(:user, role: 'admin') }

  describe 'validations' do
    it 'is valid with translations containing ro' do
      pn = build(:push_notification, created_by: admin)
      expect(pn).to be_valid
    end

    it 'is invalid without translations' do
      pn = build(:push_notification, created_by: admin, translations: nil)
      expect(pn).not_to be_valid
    end

    it 'is invalid without a ro translation' do
      pn = build(:push_notification, created_by: admin,
                                     translations: { 'en' => { 'title' => 'Hi', 'body' => 'There' } })
      expect(pn).not_to be_valid
    end

    it 'is invalid when ro translation is missing title' do
      pn = build(:push_notification, created_by: admin,
                                     translations: { 'ro' => { 'body' => 'Buna' } })
      expect(pn).not_to be_valid
    end

    it 'is invalid when ro translation is missing body' do
      pn = build(:push_notification, created_by: admin,
                                     translations: { 'ro' => { 'title' => 'Salut' } })
      expect(pn).not_to be_valid
    end
  end

  describe '#translation_for' do
    let(:pn) do
      build(:push_notification, created_by: admin, translations: {
              'ro' => { 'title' => 'Salut', 'body' => 'Buna ziua' },
              'en' => { 'title' => 'Hello', 'body' => 'Good day' }
            })
    end

    it 'returns the matching language translation' do
      expect(pn.translation_for('en-US')).to eq({ 'title' => 'Hello', 'body' => 'Good day' })
    end

    it 'falls back to ro when language not available' do
      expect(pn.translation_for('de-DE')).to eq({ 'title' => 'Salut', 'body' => 'Buna ziua' })
    end

    it 'falls back to ro when language is nil' do
      expect(pn.translation_for(nil)).to eq({ 'title' => 'Salut', 'body' => 'Buna ziua' })
    end
  end

  describe '#image_url' do
    it 'returns nil when no directus_file_id' do
      pn = build(:push_notification, created_by: admin, directus_file_id: nil)
      expect(pn.image_url).to be_nil
    end

    it 'returns directus asset URL when file id present' do
      pn = build(:push_notification, created_by: admin,
                                     directus_file_id: '187aa1d8-8823-4ed6-8f2d-33629e800dcc')
      expect(pn.image_url).to eq(
        "#{ENV.fetch('DIRECTUS_URL', 'https://adminctevents.chiciudean.family')}/assets/187aa1d8-8823-4ed6-8f2d-33629e800dcc"
      )
    end
  end
end
