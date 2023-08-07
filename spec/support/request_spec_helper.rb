# frozen_string_literal: true

module RequestSpecHelper
  def json
    JSON.parse(response.body)
  end

  def default_headers
    { CONTENT_TYPE: 'application/json' }
  end
  
  def auth_headers(token, with_default_headers: true)
    auth = { 'Authorization' => "Bearer #{token}" }
    with_default_headers ? default_headers.merge(auth) : auth
  end
  
  def authorized_headers_for(user)
    token = user.tokens['access_token']
    { Authorization: "Bearer #{token}", CONTENT_TYPE: 'application/json' }
  end
end