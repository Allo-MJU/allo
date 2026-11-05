package ai.allo.car.sync

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.util.Log
import ai.allo.car.R

/**
 * 화면이 꺼지거나 다른 앱이 올라와도 신호 수집·전송을 유지하기 위한 포그라운드 서비스. 로직은 SessionManager 에 있다.
 *
 * - 앱이 앞에 보이지 않을 때 startForeground 를 부르면 Android 12+ 는 ForegroundServiceStartNotAllowedException 으로
 *   프로세스를 죽인다 (2026-11-04 에뮬레이터에서 SystemUI 가 재시작되는 동안 발생). 실패하면 서비스만 접고 앱은 계속 돈다.
 *   MainActivity.onStart 가 화면에 보일 때 다시 시작한다.
 * - START_NOT_STICKY: 프로세스가 죽은 뒤 서비스만 되살아나면 SessionManager 는 시작되지 않아
 *   "실행 중" 알림만 뜨고 아무것도 수집하지 않는다. 그래서 되살리지 않는다.
 */
class SessionService : Service() {
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.notif_channel), NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!goForeground()) stopSelf(startId)
        return START_NOT_STICKY
    }

    /** dataSync 포그라운드 서비스는 Android 15 부터 하루 6시간 limit. 넘으면 서비스만 접는다 (수집은 앱이 앞에 있는 동안 계속) */
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w(TAG, "foreground service timeout type=$fgsType")
        stopSelf(startId)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun goForeground(): Boolean = try {
        val n = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.notif_running))
            .setOngoing(true)
            .build()
        startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        true
    } catch (e: Exception) {   // ForegroundServiceStartNotAllowedException(API 31+) · SecurityException
        Log.w(TAG, "startForeground not allowed: ${e.javaClass.simpleName}")
        false
    }

    private companion object {
        const val CHANNEL = "allo_session"
        const val TAG = "SessionService"
    }
}
