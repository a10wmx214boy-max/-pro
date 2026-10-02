package com.shorja.chat

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shorja.chat.model.*
import com.shorja.chat.ui.ChatState
import com.shorja.chat.ui.ChatViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { MessagingApp() } }
    }
}

@Composable
fun MessagingApp(vm: ChatViewModel = viewModel()) {
    val state by vm.state.collectAsState()
    var chat by remember { mutableStateOf<Conversation?>(null) }
    if (!state.session) LoginScreen(state.loading, state.error, vm)
    else if (chat != null) ChatScreen(chat!!, state, vm) { chat = null }
    else HomeScreen(state, vm) { chat = it }
}

@Composable
private fun LoginScreen(loading: Boolean, error: String?, vm: ChatViewModel) {
    var register by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
        Text("مراسلة الشورجة", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(24.dp))
        if (register) {
            OutlinedTextField(username, { username = it }, label = { Text("اسم المستخدم") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(name, { name = it }, label = { Text("الاسم") }, modifier = Modifier.fillMaxWidth())
        }
        OutlinedTextField(email, { email = it }, label = { Text("البريد الإلكتروني") }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(password, { password = it }, label = { Text("كلمة المرور") }, modifier = Modifier.fillMaxWidth())
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        Button(enabled = !loading, onClick = { if (register) vm.register(email, password, username, name) else vm.login(email, password) }, modifier = Modifier.fillMaxWidth().padding(top = 16.dp)) {
            Text(if (register) "إنشاء حساب" else "تسجيل الدخول")
        }
        TextButton(onClick = { register = !register }) { Text(if (register) "لدي حساب بالفعل" else "حساب جديد") }
    }
}

@Composable
private fun HomeScreen(state: ChatState, vm: ChatViewModel, onOpen: (Conversation) -> Unit) {
    var query by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("المحادثات", style = MaterialTheme.typography.headlineSmall)
            TextButton(onClick = vm::logout) { Text("خروج") }
        }
        OutlinedTextField(query, { query = it; vm.search(it) }, label = { Text("ابحث عن مستخدم") }, modifier = Modifier.fillMaxWidth())
        state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        if (query.isNotBlank()) {
            LazyColumn {
                items(state.profiles, key = { it.id }) { profile ->
                    ListItem(
                        headlineContent = { Text(profile.display_name ?: profile.name ?: profile.username ?: "مستخدم") },
                        supportingContent = { Text("@${profile.username ?: ""}") },
                        modifier = Modifier.fillMaxWidth().clickable { vm.startChat(profile, onOpen) }
                    )
                }
            }
        } else {
            LazyColumn {
                items(state.conversations, key = { it.id }) { conversation ->
                    ListItem(
                        headlineContent = { Text(conversation.title ?: "محادثة") },
                        supportingContent = { Text(conversation.kind) },
                        modifier = Modifier.fillMaxWidth().clickable { vm.open(conversation); onOpen(conversation) }
                    )
                }
            }
        }
    }
}

@Composable
private fun ChatScreen(conversation: Conversation, state: ChatState, vm: ChatViewModel, onBack: () -> Unit) {
    var text by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("رجوع") }
            Text(conversation.title ?: "محادثة", style = MaterialTheme.typography.headlineSmall)
        }
        LazyColumn(Modifier.weight(1f)) {
            items(state.messages, key = { it.id }) { message ->
                ListItem(
                    headlineContent = { Text(if (message.deleted_at != null) "تم حذف هذه الرسالة" else message.content ?: "") },
                    supportingContent = { Text(if (message.is_edited) "تم التعديل" else message.created_at) }
                )
            }
        }
        Row(Modifier.fillMaxWidth()) {
            OutlinedTextField(text, { text = it }, label = { Text("اكتب رسالة") }, modifier = Modifier.weight(1f))
            Button(enabled = text.isNotBlank(), onClick = { vm.send(conversation, text); text = "" }) { Text("إرسال") }
        }
    }
}
