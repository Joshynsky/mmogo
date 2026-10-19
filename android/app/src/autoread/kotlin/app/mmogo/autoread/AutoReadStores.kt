package app.mmogo.autoread

import android.content.Context
import java.io.File

/** The one process-wide HeldStore (claims are per instance, so the bridge must share this one). */
object AutoReadStores {
    @Volatile
    private var held: HeldStore? = null

    fun held(context: Context): HeldStore {
        val h = held
        if (h != null) return h
        synchronized(this) {
            val again = held
            if (again != null) return again
            val created = HeldStore(File(context.applicationContext.cacheDir, "autoread_held"))
            held = created
            return created
        }
    }
}
