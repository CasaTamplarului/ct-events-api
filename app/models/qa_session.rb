# frozen_string_literal: true

class QaSession < ApplicationRecord
  belongs_to :event
  belongs_to :created_by_user, class_name: 'User'
  has_many :qa_session_translations, dependent: :destroy
  has_many :qa_questions, dependent: :destroy

  enum :status, { open: 0, closed: 1 }

  validates :code, presence: true, uniqueness: true

  before_validation :generate_code, on: :create, if: -> { code.blank? }

  def name_for(lang)
    translations = qa_session_translations.to_a
    translation = translations.find { |t| t.languages_code == lang } || translations.first
    translation&.name
  end

  private

    def generate_code
      loop do
        self.code = SecureRandom.alphanumeric(8).upcase
        break unless QaSession.exists?(code: code)
      end
    end
end
