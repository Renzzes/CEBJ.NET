package com.koneksikfi.gcashcompanion.ui

import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.Fragment
import com.koneksikfi.gcashcompanion.data.EventLog
import com.koneksikfi.gcashcompanion.data.PoolStore
import com.koneksikfi.gcashcompanion.data.Prefs
import com.koneksikfi.gcashcompanion.databinding.FragmentSetupBinding

class SetupFragment : Fragment() {
    private var _binding: FragmentSetupBinding? = null
    private val binding get() = _binding!!

    private val pickJson = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@registerForActivityResult
        try {
            val text = requireContext().contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                ?: run {
                    binding.txtImportStatus.text = "Could not read file"
                    return@registerForActivityResult
                }
            val result = PoolStore(requireContext()).importExportJson(text)
            binding.txtImportStatus.text = result.message
            EventLog(requireContext()).add(if (result.ok) "OK" else "ERR", result.message)
            Toast.makeText(requireContext(), result.message, Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            binding.txtImportStatus.text = e.message
            Toast.makeText(requireContext(), e.message, Toast.LENGTH_LONG).show()
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentSetupBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val prefs = Prefs(requireContext())
        binding.inputSecret.setText(prefs.appSecret)
        binding.inputRouterUrl.setText(prefs.routerBaseUrl)
        val remaining = PoolStore(requireContext()).remainingCount()
        binding.txtImportStatus.text =
            if (remaining > 0) "Pool on device: $remaining codes remaining"
            else "No pool imported yet"

        binding.btnImportPool.setOnClickListener {
            pickJson.launch(arrayOf("application/json", "text/*", "*/*"))
        }
        binding.btnSaveSetup.setOnClickListener {
            prefs.appSecret = binding.inputSecret.text?.toString().orEmpty()
            prefs.routerBaseUrl = binding.inputRouterUrl.text?.toString().orEmpty()
            EventLog(requireContext()).add("OK", "Setup saved")
            Toast.makeText(requireContext(), "Setup saved", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
