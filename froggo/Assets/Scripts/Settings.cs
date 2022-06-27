using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using TMPro;

public static class Settings {
    public static string muteKey = "mute";
    public static bool soundPlayable {
        get {
            return PlayerPrefs.GetInt(muteKey, 1) == 1;
        }
        set {
            PlayerPrefs.SetInt(muteKey, value == true ? 1 : 0);
            PlayerPrefs.Save();
        }
    }

    public static void play(AudioSource source) {
        if(soundPlayable) {
            source.Play();
        } else {
            source.Stop();
        }
    }
}
