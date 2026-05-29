# frozen_string_literal: true

module LocaleSetter
  extend ActiveSupport::Concern

  private

  def set_locale
    raw_lang = try(:current_user)&.language || params[:language]
    lang = raw_lang.to_s.split('-').first
    I18n.locale = lang.present? && I18n.available_locales.include?(lang.to_sym) ? lang.to_sym : I18n.default_locale
  end
end
