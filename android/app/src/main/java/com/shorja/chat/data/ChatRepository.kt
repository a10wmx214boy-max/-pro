package com.shorja.chat.data

import com.shorja.chat.model.*
import io.github.jan.supabase.auth.providers.Email
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.Flow
import java.time.Instant

class ChatRepository {
    val currentUserId: String? get() = supabase.auth.currentUserOrNull()?.id
    suspend fun signIn(email: String, password: String) = supabase.auth.signInWith(Email) { this.email = email; this.password = password }
    suspend fun signUp(email: String, password: String, username: String, displayName: String) {
        supabase.auth.signUpWith(Email) { this.email = email; this.password = password }
        currentUserId?.let { supabase.from("profiles").update(mapOf("username" to username, "display_name" to displayName, "name" to displayName)) { filter { eq("id", it) } } }
    }
    suspend fun signOut() = supabase.auth.signOut()
    suspend fun searchProfiles(query: String): List<Profile> = supabase.from("profiles").select().decodeList<Profile>().filter { p -> (p.username ?: "").contains(query, true) || (p.display_name ?: p.name ?: "").contains(query, true) }.take(30)
    suspend fun myConversations(): List<Conversation> {
        val uid = currentUserId ?: return emptyList()
        val ids = supabase.from("conversation_members").select { filter { eq("user_id", uid) } }.decodeList<ConversationMember>().map { it.conversation_id }
        if (ids.isEmpty()) return emptyList()
        return supabase.from("conversations").select { filter { isIn("id", ids) }; order("updated_at", Order.DESCENDING) }.decodeList()
    }
    suspend fun getOrCreateDirect(otherUserId: String): Conversation {
        val uid = currentUserId ?: error("session_expired")
        val my = myConversations()
        for (c in my.filter { it.kind == "DIRECT" }) {
            val members = supabase.from("conversation_members").select { filter { eq("conversation_id", c.id) } }.decodeList<ConversationMember>()
            if (members.any { it.user_id == otherUserId }) return c
        }
        val created = supabase.from("conversations").insert(ConversationInsert("DIRECT", uid)) { select() }.decodeSingle<Conversation>()
        supabase.from("conversation_members").insert(listOf(MemberInsert(created.id, uid, "OWNER"), MemberInsert(created.id, otherUserId)))
        return created
    }
    suspend fun messages(conversationId: String): List<ChatMessage> = supabase.from("chat_messages").select { filter { eq("conversation_id", conversationId) }; order("created_at", Order.ASCENDING); limit(100) }.decodeList()
    suspend fun sendMessage(conversationId: String, text: String, replyTo: String? = null): ChatMessage {
        val uid = currentUserId ?: error("session_expired")
        require(text.trim().isNotEmpty() && text.length <= 10000)
        return supabase.from("chat_messages").insert(MessageInsert(conversationId, uid, text.trim(), reply_to_message_id = replyTo)) { select() }.decodeSingle()
    }
    suspend fun editMessage(id: String, text: String) = supabase.from("chat_messages").update(mapOf("content" to text.trim(), "updated_at" to Instant.now().toString(), "is_edited" to true)) { filter { eq("id", id) } }
    suspend fun deleteMessage(id: String) = supabase.from("chat_messages").update(mapOf("content" to null, "deleted_at" to Instant.now().toString(), "updated_at" to Instant.now().toString())) { filter { eq("id", id) } }
    fun messageFlow(conversationId: String): Flow<List<ChatMessage>> = supabase.from("chat_messages").selectAsFlow(ChatMessage::id) { filter { eq("conversation_id", conversationId) } }
    suspend fun markRead(conversationId: String) { currentUserId?.let { supabase.from("conversation_members").update(mapOf("last_read_at" to Instant.now().toString())) { filter { eq("conversation_id", conversationId); eq("user_id", it) } } } }
}
