Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "lab" => "lab#index"
  namespace :api do
    namespace :v1 do
      resources :classifications, only: :create
    end
  end
end
