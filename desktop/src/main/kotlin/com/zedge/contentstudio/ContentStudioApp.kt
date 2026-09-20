package com.zedge.contentstudio

import android.app.Application
import com.zedge.contentstudio.core.MetaNotifier
import com.zedge.contentstudio.data.GitHubRepo
import com.zedge.contentstudio.data.QueueRepository
import com.zedge.contentstudio.data.VpnRepo
import com.zedge.contentstudio.domain.SpecialDays
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch

/** Manual dependency graph - one instance of every service for the whole process. */
@OptIn(kotlinx.coroutines.FlowPreview::class)
class ContentStudioApp : Application() {
    lateinit var queueRepo: QueueRepository
        private set
    lateinit var gitHub: GitHubRepo
        private set
    lateinit var vpn: VpnRepo
        private set
    lateinit var specialDays: SpecialDays
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        queueRepo = QueueRepository(this)
        gitHub = GitHubRepo(this, queueRepo.http, queueRepo.db("zedge1"))
        vpn = VpnRepo({ key -> queueRepo.db(key) }, gitHub)
        specialDays = SpecialDays(this, queueRepo.http)
        MetaNotifier.ensureChannel(this)
        // v23 metadata guard: watch the active account's queue and notify about NEW files without metadata.
        appScope.launch {
            combine(queueRepo.activeKey, queueRepo.queue, queueRepo.connected) { key, q, ok -> Triple(key, q, ok) }
                .debounce(1500)
                .collect { (key, q, ok) ->
                    if (!ok) return@collect
                    val fresh = MetaNotifier.onQueue(this@ContentStudioApp, key, q)
                    if (fresh.isNotEmpty()) metaEvents.tryEmit(fresh.size)
                }
        }
    }

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    /** Number of newly detected files without metadata (for an in-app snackbar). */
    val metaEvents = MutableSharedFlow<Int>(extraBufferCapacity = 8)

    companion object {
        lateinit var instance: ContentStudioApp
            private set
    }
}
