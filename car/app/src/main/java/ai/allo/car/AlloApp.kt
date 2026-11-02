package ai.allo.car

import android.app.Application
import ai.allo.car.sync.SessionManager

class AlloApp : Application() {
    /** 앱 전체에 하나. 세션 생성, 신호 수집, Firebase 전송을 소유한다. */
    lateinit var session: SessionManager
        private set

    override fun onCreate() {
        super.onCreate()
        session = SessionManager(this)
    }
}
