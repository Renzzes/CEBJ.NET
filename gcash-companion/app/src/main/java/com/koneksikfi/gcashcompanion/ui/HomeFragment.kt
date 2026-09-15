package com.koneksikfi.gcashcompanion.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import com.koneksikfi.gcashcompanion.data.EventLog
import com.koneksikfi.gcashcompanion.data.PoolStore
import com.koneksikfi.gcashcompanion.data.Prefs
import com.koneksikfi.gcashcompanion.databinding.FragmentHomeBinding

class HomeFragment : Fragment() {
    private var _binding: FragmentHomeBinding? = null
    private val binding get() = _binding!!

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentHomeBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val prefs = Prefs(requireContext())
        binding.switchListening.isChecked = prefs.listeningEnabled
        binding.switchListening.setOnCheckedChangeListener { _, checked ->
            prefs.listeningEnabled = checked
            refresh()
        }
        refresh()
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun refresh() {
        val ctx = context ?: return
        val prefs = Prefs(ctx)
        binding.txtListenStatus.text =
            if (prefs.listeningEnabled) getString(com.koneksikfi.gcashcompanion.R.string.listening_on)
            else getString(com.koneksikfi.gcashcompanion.R.string.listening_off)
        binding.txtPoolSummary.text = PoolStore(ctx).summaryLines().joinToString("\n")
        val events = EventLog(ctx).lines()
        binding.txtEvents.text = if (events.isEmpty()) "No events yet" else events.joinToString("\n")
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
