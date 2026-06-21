# frozen_string_literal: true

class QaQuestionsChannel < ApplicationCable::Channel
  def subscribed
    code = params[:code].to_s.strip
    return reject if code.blank?
    return reject unless QaSession.exists?(code: code)

    stream_from "qa_questions_#{code}"
  end
end
