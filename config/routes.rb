Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "lab" => "lab#index"
  post "lab/run" => "lab#run", as: :lab_run
  namespace :api do
    namespace :v1 do
      resources :classifications, only: :create
    end
  end
end
