package com.zedge.contentstudio

import android.app.Application
import com.zedge.contentstudio.data.GitHubRepo
import com.zedge.contentstudio.data.QueueRepository
import com.zedge.contentstudio.domain.SpecialDays

/** Manual dependency graph - one instance of every service for the whole process. */
class ContentStudioApp : Application() {
    lateinit var queueRepo: QueueRepository
        private set
    lateinit var gitHub: GitHubRepo
        private set
    lateinit var specialDays: SpecialDays
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        queueRepo = QueueRepository(this)
        gitHub = GitHubRepo(this, queueRepo.http, queueRepo.db("zedge1"))
        specialDays = SpecialDays(this, queueRepo.http)
    }

    companion object {
        lateinit var instance: ContentStudioApp
            private set
    }
}
