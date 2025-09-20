using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

public class UI_MenuButton : MonoBehaviour
{
    public Button btnStart;

    public AudioSource click;

    public bool mainMenu;

    void Start()
    {
        Button btn = GetComponent<Button>();
        btn.onClick.AddListener(TaskOnClick);
        click = GetComponent<AudioSource>();
    }

    void TaskOnClick()
    {
        Settings.play(click);
        SceneManager.LoadScene("MainMenu");
    }
}