require "rails_helper"

RSpec.describe "ChatChannelMemberships", type: :request do
  let(:user) { create(:user) }
  let(:second_user) { create(:user) }
  let(:chat_channel) { create(:chat_channel) }

  before do
    sign_in user
    chat_channel.add_users([user])
  end

  describe "GET /chat_channel_memberships" do
    context "Pending Invitations exists" do
      before do
        user.add_role(:super_admin)
        post "/chat_channel_memberships", params: {
          chat_channel_membership: {
            invitation_usernames: "#{second_user.username}",
            chat_channel_id: chat_channel.id
          }
        }
      end

      it "shows chat_channel_memberships list pending invitation" do
        sign_in second_user
        get "/chat_channel_memberships"
        expect(response.body).to include "Pending Invitations"
        expect(response.body).to include "#{chat_channel.channel_name}"
      end
    end

    context "No pending invitation" do
      it "shows chat_channel_memberships list pending invitation" do
        sign_in second_user
        get "/chat_channel_memberships"
        expect(response.body).to include "You have no pending invitations"
      end
    end
  end

  describe "GET /chat_channel_memberships/find_by_chat_channel_id" do
    context "user is logged in" do
      before do
        chat_channel.add_users([second_user])
      end

      it "returns chat channel membership details" do
        sign_in second_user
        get "/chat_channel_memberships/find_by_chat_channel_id", params: {chat_channel_id: chat_channel.id}
        expected_keys = %w(id status chat_channel_id last_opened_at channel_text
                           channel_last_message_at channel_status channel_username
                           channel_type channel_name channel_image
                           channel_modified_slug channel_messages_count)
        expect(JSON.parse(response.body).keys).to(match_array(expected_keys))
      end
    end

    context "user is not logged in" do
      it "renders not_found" do
        expect do
          get "/chat_channel_memberships/find_by_chat_channel_id", params: {}
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "GET /chat_channel_memberships/:id/edit" do
    before do
      chat_channel.add_users([second_user])
    end

    let(:chat_channel_membership) { chat_channel.chat_channel_memberships.where(user_id: second_user.id).first }

    context "user is" do
      context "not logged in" do
        it "raise Pundit::NotAuthorizedError" do
          expect do
            get "/chat_channel_memberships/#{chat_channel_membership.id}/edit"
          end.to raise_error(Pundit::NotAuthorizedError)
        end
      end

      context "user is logged in and channel id is wrong" do
        it "raise ActiveRecord::RecordNotFound" do
          sign_in second_user
          expect do
            get "/chat_channel_memberships/ERW/edit"
          end.to raise_error(ActiveRecord::RecordNotFound)
        end
      end

      context "channel member" do
        it "allows user to view channel members" do
          sign_in second_user
          get "/chat_channel_memberships/#{chat_channel_membership.id}/edit"
          expect(response.body).to include("Members")
          expect(response.body).to include("#{user.username}")
          expect(response.body).to include("#{second_user.username}")
          expect(response.body).not_to include("Pending Invitations")
        end
      end

      context "channel moderator" do
        it "allows user to view channel members" do
          sign_in second_user
          chat_channel_membership.update(role: "mod")
          get "/chat_channel_memberships/#{chat_channel_membership.id}/edit"
          expect(response.body).to include("Members")
          expect(response.body).to include("#{user.username}")
          expect(response.body).to include("#{second_user.username}")
          expect(response.body).to include("Pending Invitations")
          expect(response.body).to include("You are a channel mod")
        end
      end
    end
  end

  describe "POST /chat_channel_memberships" do
    context "user is" do
      context "super admin" do
        it "creates chat channel invitation" do
          user.add_role(:super_admin)
          chat_channel_members_count = ChatChannelMembership.all.size
          post "/chat_channel_memberships", params: {
            chat_channel_membership: {
              invitation_usernames: "#{second_user.username}",
              chat_channel_id: chat_channel.id
            }
          }
          expect(ChatChannelMembership.all.size).to eq(chat_channel_members_count + 1)
          expect(ChatChannelMembership.last.status).to eq("pending")
        end
      end

      context "channel moderator" do
        it "creates chat channel invitation" do
          chat_channel.chat_channel_memberships.where(user_id: user.id).update(role: "mod")
          chat_channel_members_count = ChatChannelMembership.all.size
          post "/chat_channel_memberships", params: {
            chat_channel_membership: {
              invitation_usernames: "#{second_user.username}",
              chat_channel_id: chat_channel.id
            }
          }
          expect(ChatChannelMembership.all.size).to eq(chat_channel_members_count + 1)
          expect(ChatChannelMembership.last.status).to eq("pending")
        end
      end

      context "not authorized to add channel membership" do
        it "raise Pundit::NotAuthorizedError" do
          expect do
            post "/chat_channel_memberships", params: {
              chat_channel_membership: {
                invitation_usernames: "#{second_user.username}",
                chat_channel_id: chat_channel.id
              }
            }
          end.to raise_error(Pundit::NotAuthorizedError)
        end
      end
    end
  end

  describe "PUT /chat_channel_memberships/:id" do
    before do
      user.add_role(:super_admin)
      post "/chat_channel_memberships", params: {
        chat_channel_membership: {
          invitation_usernames: "#{second_user.username}",
          chat_channel_id: chat_channel.id
        }
      }
    end

    context "second user accept invitation" do
      it "sets chat channl membership status to rejected" do
        membership = ChatChannelMembership.last
        sign_in second_user
        put "/chat_channel_memberships/#{membership.id}", params: {
          chat_channel_membership: {
            user_action: "accept"
          }
        }
        expect(ChatChannelMembership.find(membership.id).status).to eq("active")
        expect(response).to(redirect_to("/chat_channel_memberships"))
      end
    end

    context "second user rejects invitation" do
      it "sets chat channl membership status to rejected" do
        membership = ChatChannelMembership.last
        sign_in second_user
        put "/chat_channel_memberships/#{membership.id}", params: {
          chat_channel_membership: {
            user_action: "reject"
          }
        }
        expect(ChatChannelMembership.find(membership.id).status).to eq("rejected")
      end
    end

    context "user not logged in" do
      it "raise Pundit::NotAuthorizedError" do
        membership = ChatChannelMembership.last
        expect do
          put "/chat_channel_memberships/#{membership.id}", params: {
            chat_channel_membership: { user_action: "accept" }
          }
        end.to raise_error(Pundit::NotAuthorizedError)
      end
    end

    context "user is unauthorized" do
      it "raise Pundit::NotAuthorizedError" do
        membership = ChatChannelMembership.last
        sign_in user
        expect do
          put "/chat_channel_memberships/#{membership.id}", params: {
            chat_channel_membership: { user_action: "accept" }
          }
        end.to raise_error(Pundit::NotAuthorizedError)
      end
    end
  end

  describe "DELETE /chat_channel_memberships/:id" do
    context "user is logged in" do
      it "leaves chat channel" do
        chat_channel.add_users([second_user])
        membership = ChatChannelMembership.last
        sign_in second_user
        delete "/chat_channel_memberships/#{membership.id}", params: {}
        expect(ChatChannelMembership.find(membership.id).status).to eq("left_channel")
        expect(response).to(redirect_to("/chat_channel_memberships"))
      end
    end

    context "user is not logged in" do
      it "raise Pundit::NotAuthorizedError" do
        chat_channel.add_users([second_user])
        membership = ChatChannelMembership.last
        expect do
          delete "/chat_channel_memberships/#{membership.id}", params: {}
        end.to(raise_error(Pundit::NotAuthorizedError))
      end
    end
  end
end
