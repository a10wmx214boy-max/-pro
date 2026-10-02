package com.shorja.chat.model

import kotlinx.serialization.Serializable

@Serializable data class Profile(val id: String, val username: String? = null, val display_name: String? = null, val name: String? = null, val bio: String? = null, val avatar_url: String? = null, val last_seen_at: String? = null)
@Serializable data class Conversation(val id: String, val kind: String, val title: String? = null, val avatar_url: String? = null, val created_by: String, val updated_at: String? = null)
@Serializable data class ConversationMember(val conversation_id: String, val user_id: String, val role: String = "MEMBER", val last_read_at: String? = null)
@Serializable data class ChatMessage(val id: String, val conversation_id: String, val sender_id: String, val content: String? = null, val message_type: String = "TEXT", val reply_to_message_id: String? = null, val created_at: String, val updated_at: String? = null, val deleted_at: String? = null, val is_edited: Boolean = false)
@Serializable data class ConversationInsert(val kind: String, val created_by: String, val title: String? = null)
@Serializable data class MemberInsert(val conversation_id: String, val user_id: String, val role: String = "MEMBER")
@Serializable data class MessageInsert(val conversation_id: String, val sender_id: String, val content: String, val message_type: String = "TEXT", val reply_to_message_id: String? = null)
