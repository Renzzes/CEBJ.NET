package com.koneksikfi.gcashcompanion

import android.app.Application

class GcashApp : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    companion object {
        lateinit var instance: GcashApp
            private set
    }
}
