package com.shorja.chat.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.shorja.chat.data.ChatRepository
import com.shorja.chat.model.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ChatState(val loading: Boolean = false, val session: Boolean = false, val conversations: List<Conversation> = emptyList(), val profiles: List<Profile> = emptyList(), val messages: List<ChatMessage> = emptyList(), val error: String? = null)
class ChatViewModel(private val repo: ChatRepository = ChatRepository()) : ViewModel() {
    private val _state = MutableStateFlow(ChatState(session = repo.currentUserId != null)); val state: StateFlow<ChatState> = _state.asStateFlow()
    fun login(email: String, password: String) = work { repo.signIn(email, password); refresh() }
    fun register(email: String, password: String, username: String, name: String) = work { repo.signUp(email, password, username, name); refresh() }
    fun logout() = work { repo.signOut(); _state.value = ChatState() }
    fun refresh() = work { _state.value = _state.value.copy(session = true, conversations = repo.myConversations(), error = null) }
    fun search(q: String) = work { _state.value = _state.value.copy(profiles = repo.searchProfiles(q), error = null) }
    fun open(c: Conversation) = work { _state.value = _state.value.copy(messages = repo.messages(c.id), error = null); repo.markRead(c.id) }
    fun send(c: Conversation, text: String) = work { repo.sendMessage(c.id, text); open(c) }
    fun startChat(profile: Profile, onReady: (Conversation) -> Unit) = work { onReady(repo.getOrCreateDirect(profile.id)) }
    fun clearError() { _state.value = _state.value.copy(error = null) }
    private fun work(block: suspend () -> Unit) { viewModelScope.launch { _state.value = _state.value.copy(loading = true, error = null); runCatching { block() }.onFailure { _state.value = _state.value.copy(error = friendly(it)) }; _state.value = _state.value.copy(loading = false) } }
    private fun friendly(t: Throwable) = when { t.message?.contains("session", true) == true -> "انتهت الجلسة، سجّل الدخول من جديد"; else -> "تعذر تنفيذ العملية. تحقق من الاتصال وحاول مرة أخرى." }
}
