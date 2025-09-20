using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

public class UI_StartButton : MonoBehaviour
{
    public Button btnStart;

	public bool mainMenu;

    public AudioSource click;

	void Start () {
        click = GetComponent<AudioSource>();
		Button btn = GetComponent<Button>();
		btn.onClick.AddListener(TaskOnClick);
	}

	void TaskOnClick(){
        Settings.play(click);
		SceneManager.LoadScene("GameScene");
	}
}
