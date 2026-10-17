package com.toyako.music

import android.content.ComponentName
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture

class MainActivity : ComponentActivity() {
    private var controllerFuture: ListenableFuture<MediaController>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val token = SessionToken(this, ComponentName(this, PlaybackService::class.java))
        controllerFuture = MediaController.Builder(this, token).buildAsync()
        setContent {
            val tracks = remember { mutableStateListOf<TrackEntry>() }
            var controller by remember { mutableStateOf<MediaController?>(null) }
            var isPlaying by remember { mutableStateOf(false) }
            var currentTitle by remember { mutableStateOf("Nothing playing") }
            var currentIndex by remember { mutableStateOf(-1) }

            DisposableEffect(Unit) {
                val future = controllerFuture
                if (future != null) {
                    future.addListener({
                        try { controller = future.get() } catch (_: Exception) { }
                    }, mainExecutor)
                }
                onDispose { }
            }
            DisposableEffect(controller) {
                val c = controller
                val listener = object : Player.Listener {
                    override fun onIsPlayingChanged(playing: Boolean) { isPlaying = playing }
                    override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                        currentTitle = mediaItem?.mediaMetadata?.title?.toString() ?: "Nothing playing"
                        currentIndex = c?.currentMediaItemIndex ?: -1
                    }
                }
                c?.addListener(listener)
                onDispose { c?.removeListener(listener) }
            }

            val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris: List<Uri> ->
                val c = controller ?: return@rememberLauncherForActivityResult
                uris.forEach { uri ->
                    try { contentResolver.takePersistableUriPermission(uri, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) { }
                    val name = displayName(uri) ?: uri.lastPathSegment ?: "Audio track"
                    tracks.add(TrackEntry(name, uri))
                    c.addMediaItem(MediaItem.Builder().setUri(uri).setMediaMetadata(MediaMetadata.Builder().setTitle(name).build()).build())
                }
                if (c.mediaItemCount > 0 && !c.isPlaying) c.prepare()
            }

            MaterialTheme(colorScheme = darkColorScheme(
                primary = Color(0xFFB9A6FF), background = Color(0xFF111114), surface = Color(0xFF1D1D23)
            )) {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    Column(Modifier.fillMaxSize().padding(20.dp)) {
                        Text("TOYAKO", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                        Text("Your music. Your device.", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(20.dp))
                        Button(onClick = { picker.launch(arrayOf("audio/*")) }, modifier = Modifier.fillMaxWidth()) {
                            Icon(Icons.Default.Add, contentDescription = null)
                            Text("  Import music")
                        }
                        Spacer(Modifier.height(18.dp))
                        Text("LIBRARY  ·  ${tracks.size} TRACKS", style = MaterialTheme.typography.labelMedium, color = Color.LightGray)
                        Spacer(Modifier.height(8.dp))
                        if (tracks.isEmpty()) {
                            Card(modifier = Modifier.fillMaxWidth()) {
                                Column(Modifier.padding(18.dp)) {
                                    Text("Your library is empty", fontWeight = FontWeight.SemiBold)
                                    Text("Import audio files from your device to start listening.", color = Color.LightGray)
                                }
                            }
                        } else {
                            LazyColumn(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                itemsIndexed(tracks) { index, track ->
                                    Card(onClick = {
                                        controller?.let { c -> c.seekTo(index, 0); c.play() }
                                    }, modifier = Modifier.fillMaxWidth()) {
                                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                            Column(Modifier.weight(1f)) {
                                                Text(track.title, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Medium)
                                                Text("Local audio", style = MaterialTheme.typography.bodySmall, color = Color.LightGray)
                                            }
                                            if (index == currentIndex) Text("NOW PLAYING", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelSmall)
                                        }
                                    }
                                }
                            }
                        }
                        Spacer(Modifier.height(12.dp))
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(14.dp)) {
                                Text(currentTitle, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                                    IconButton(onClick = { controller?.seekToPreviousMediaItem() }) { Icon(Icons.Default.SkipPrevious, "Previous") }
                                    IconButton(onClick = { controller?.let { if (it.isPlaying) it.pause() else { if (it.playbackState == Player.STATE_IDLE) it.prepare(); it.play() } } }) {
                                        Icon(if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, if (isPlaying) "Pause" else "Play")
                                    }
                                    IconButton(onClick = { controller?.seekToNextMediaItem() }) { Icon(Icons.Default.SkipNext, "Next") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }

    override fun onDestroy() {
        controllerFuture?.let { MediaController.releaseFuture(it) }
        controllerFuture = null
        super.onDestroy()
    }
}

data class TrackEntry(val title: String, val uri: Uri)
