package com.koneksikfi.gcashcompanion.ui

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import com.koneksikfi.gcashcompanion.databinding.FragmentPermissionsBinding
import com.koneksikfi.gcashcompanion.sms.SmsSender

class PermissionsFragment : Fragment() {
    private var _binding: FragmentPermissionsBinding? = null
    private val binding get() = _binding!!

    private val smsPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { refresh() }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentPermissionsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        binding.btnNotifAccess.setOnClickListener {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
        binding.btnSms.setOnClickListener {
            smsPermission.launch(Manifest.permission.SEND_SMS)
        }
        binding.btnBattery.setOnClickListener {
            val ctx = requireContext()
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${ctx.packageName}")
            }
            try {
                startActivity(intent)
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            }
        }
        refresh()
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun refresh() {
        val ctx = context ?: return
        val notifOk = isNotificationListenerEnabled(ctx)
        binding.txtNotifStatus.text =
            if (notifOk) "Notification access: ON"
            else "Notification access: OFF — required to read GCash alerts"
        binding.txtNotifStatus.setTextColor(
            ContextCompat.getColor(
                ctx,
                if (notifOk) com.koneksikfi.gcashcompanion.R.color.ks_ok
                else com.koneksikfi.gcashcompanion.R.color.ks_err
            )
        )

        val smsOk = SmsSender.hasPermission(ctx)
        binding.txtSmsStatus.text =
            if (smsOk) "SMS permission: ON"
            else "SMS permission: OFF — required to text voucher codes"
        binding.txtSmsStatus.setTextColor(
            ContextCompat.getColor(
                ctx,
                if (smsOk) com.koneksikfi.gcashcompanion.R.color.ks_ok
                else com.koneksikfi.gcashcompanion.R.color.ks_err
            )
        )

        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        val battOk = pm.isIgnoringBatteryOptimizations(ctx.packageName)
        binding.txtBatteryStatus.text =
            if (battOk) "Battery optimization: unrestricted"
            else "Battery optimization: restricted — listening may sleep"
        binding.txtBatteryStatus.setTextColor(
            ContextCompat.getColor(
                ctx,
                if (battOk) com.koneksikfi.gcashcompanion.R.color.ks_ok
                else com.koneksikfi.gcashcompanion.R.color.ks_warn
            )
        )
    }

    private fun isNotificationListenerEnabled(context: Context): Boolean {
        val flat = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        val cn = ComponentName(context, com.koneksikfi.gcashcompanion.notif.GcashNotificationListener::class.java)
        return flat.split(':').any {
            ComponentName.unflattenFromString(it)?.packageName == context.packageName &&
                (ComponentName.unflattenFromString(it)?.className == cn.className ||
                    it.contains(context.packageName))
        } || NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
