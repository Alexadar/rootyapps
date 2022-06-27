using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Fly : MonoBehaviour
{

    public Sprite fly1;

    public Sprite fly2;

    public AudioClip bzz;

    public AudioSource audioSource;

    public SpriteRenderer spriteRenderer;
    public float spawnTime = 60;

    public float speed = 0.1f;

    private float hideY = 100;

    private float hideX = -100;

    private GameObject froggo;

    public Froggo froggoScript;

    bool isFlying = false;

    private void Awake()
    {
        transform.position = new Vector3(hideX, hideY, 1);
        froggo = GameObject.Find("Froggo");
        froggoScript = froggo.GetComponent<Froggo>();
        InvokeRepeating("Spawn", spawnTime, spawnTime); //Fly flying once per N ms
        spriteRenderer = GetComponent<SpriteRenderer>();
        audioSource = GetComponent<AudioSource>();
        audioSource.clip = bzz;
        spriteRenderer.sprite = fly1;
    }

    // Start is called before the first frame update
    void Start()
    {

    }

    private void Spawn()
    {
        if (!isFlying)
        {
            Settings.play(audioSource);
            Debug.Log("Fly spawned");
            var positionX = froggo.transform.position.x - ScreenSize.GetScreenToWorldWidth / 2;
            var positionY = froggo.transform.position.y + (ScreenSize.GetScreenToWorldHeight - froggo.transform.position.y) * UnityEngine.Random.Range(0.1f, 0.45f);
            gameObject.transform.position = new Vector3(positionX, positionY, 1);
            isFlying = true;
        }
    }

    // Update is called once per frame
    void Update()
    {
        if (isFlying)
        {
            spriteRenderer.sprite = spriteRenderer.sprite == fly1 ? fly2 : fly1;
            transform.position = new Vector3(transform.position.x + speed, transform.position.y + UnityEngine.Random.Range(-0.5f, 0.5f), transform.position.z);
            if (transform.position.x > froggo.transform.position.x + ScreenSize.GetScreenToWorldWidth)
            {
                Die();
            }
        }
    }

    internal void Die()
    {
        Debug.Log("Fly died");
        transform.position = new Vector3(hideX, hideY, 1);
        isFlying = false;
        audioSource.Stop();
    }
}
