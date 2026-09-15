package com.koneksikfi.gcashcompanion

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import com.koneksikfi.gcashcompanion.databinding.ActivityMainBinding
import com.koneksikfi.gcashcompanion.ui.HomeFragment
import com.koneksikfi.gcashcompanion.ui.PermissionsFragment
import com.koneksikfi.gcashcompanion.ui.SetupFragment

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)

        if (savedInstanceState == null) {
            show(HomeFragment())
        }

        binding.bottomNav.setOnItemSelectedListener { item ->
            when (item.itemId) {
                R.id.nav_home -> show(HomeFragment())
                R.id.nav_setup -> show(SetupFragment())
                R.id.nav_perm -> show(PermissionsFragment())
            }
            true
        }
    }

    private fun show(fragment: Fragment) {
        supportFragmentManager.beginTransaction()
            .replace(R.id.content, fragment)
            .commit()
    }
}
