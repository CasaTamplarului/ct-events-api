# frozen_string_literal: true

module QaIdentifiable
  extend ActiveSupport::Concern

  def current_qa_identity
    if current_user
      { user_id: current_user.id, voter_token: nil }
    else
      { user_id: nil, voter_token: request.headers['X-QA-Token'].presence }
    end
  end
end
