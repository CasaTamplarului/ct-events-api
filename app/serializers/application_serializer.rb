# frozen_string_literal: true

class ApplicationSerializer
  include Alba::Resource

  def self.asset_url(uuid)
    return nil if uuid.blank?

    "#{ENV.fetch('DIRECTUS_PUBLIC_URL', ENV.fetch('DIRECTUS_URL', 'http://localhost:8091'))}/assets/#{uuid}"
  end

  def self.asset_type(uuid)
    return nil if uuid.blank?

    result = ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql(["SELECT type FROM directus_files WHERE id = ?", uuid])
    ).first
    result&.fetch("type", nil)
  end
end
