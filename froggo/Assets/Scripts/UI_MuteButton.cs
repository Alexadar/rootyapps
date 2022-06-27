using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using TMPro;

public class UI_MuteButton : MonoBehaviour
{
    public Button btnStart;

    public AudioSource click;

    public TMP_Text text;

    private string settingKey = "mute";

    void setText() {
        if(Settings.soundPlayable) {
            text.text = "Mute";
        } else {
            text.text = "Unmute";
        }
    }

    void Start()
    {
        Button btn = GetComponent<Button>();
        btn.onClick.AddListener(TaskOnClick);
        click = GetComponent<AudioSource>();
        text = this.GetComponentInChildren<TMP_Text>();
        setText();
    }    

    void TaskOnClick()
    {
        Settings.soundPlayable = !Settings.soundPlayable;
        Settings.play(click);
        setText();
    }
}