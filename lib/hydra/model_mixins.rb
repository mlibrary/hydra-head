module Hydra::ModelMixins
  extend ActiveSupport::Autoload
  eager_autoload do
    autoload :CommonMetadata
    autoload :RightsMetadata
  end
end
