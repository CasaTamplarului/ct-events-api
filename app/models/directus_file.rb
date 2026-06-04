# frozen_string_literal: true

class DirectusFile < ApplicationRecord
  self.table_name = 'directus_files'
  self.primary_key = 'id'
end
