using System;
using System.Collections.Generic;
using UnityEngine.SceneManagement;
using UnityEngine;
using TMPro;
using System.Collections;

public class Game : MonoBehaviour
{

    public int initialSkyscrapers = 20; //10 left - froggo here somewhere - 10 right

    public int froggoCurrentlyAt = 0;

    public float scraperSizeYDeviation = 8f;

    public float scraperWidthDeviation = 2f;

    public float scraperDistanceDeviation = 1.62f; //Golden middle

    public float initialDeltaBetweenScrapers = 10;

    public int scraperHeight = 10;

    public float scaleY = 100; //All scrapers are uniformly high

    public float scaleX = 2; //Initial scale for scraper

    public int pitHeight = -10; //Loose condition height

    public SkyScraper skyScraperPrefab;

    public GameObject bgPrefab;

    public GameObject froggo;

    public GameObject fly;

    public AudioSource audioSource;

    public Froggo froggoScript;

    public Fly flyScript;

    private GameObject counter;

    private GameObject tutorialText;

    List<SkyScraper> skyScrapers = new List<SkyScraper>();

    List<GameObject> bgs = new List<GameObject>();

    public Vector3 wind = new Vector3(0, 0, 0);

    //gamestate

    internal bool over = false;

    internal int progress = 0;

    internal int progressShift = 0;

    internal float cityLength = 0;

    internal float swapBGTresholdCameraX = 0;

    private string[] tutorialSteps = new string[] {
        "Slide down and sideways to help Freddy jump",
        "When Freddy fall, you loose",
        "Freddy jumps better, if he eats flies"
    };

    internal void tutorialForward()
    {
        var tutorialStepKey = "tutorialStep";
        var currentStep = PlayerPrefs.GetInt(tutorialStepKey, 0);
        if (++currentStep <= tutorialSteps.Length)
        {
            tutorialText.GetComponentInChildren<TextMeshPro>().SetText(tutorialSteps[currentStep - 1]);
            PlayerPrefs.SetInt(tutorialStepKey, currentStep);
            PlayerPrefs.Save();
        }
        else
        {
            tutorialText.GetComponentInChildren<TextMeshPro>().SetText(string.Empty);
        }
    }

    private void Awake()
    {
        // PlayerPrefs.SetInt("tutorialStep", 0);
        // PlayerPrefs.Save();
        froggo = GameObject.Find("Froggo");
        fly = GameObject.Find("Fly");
        froggoScript = froggo.GetComponent<Froggo>();
        flyScript = fly.GetComponent<Fly>();
        counter = GameObject.Find("Counter");
        tutorialText = GameObject.Find("TutorialText");
        audioSource = GetComponent<AudioSource>();
        Settings.play(audioSource);
        GenerateGameStart();
        spawnBGs();
    }

    private void Start()
    {
        UpdateBG();
    }

    public void spawnBGs()
    {
        float totalBGWidth = 0;
        float worldScreenHeight = Camera.main.orthographicSize * 2;
        float worldScreenWidth = worldScreenHeight / Screen.height * Screen.width;
        while (totalBGWidth <= worldScreenWidth * 2)
        {
            var bg = Instantiate<GameObject>(bgPrefab);
            var bgRenderer = bg.GetComponent<SpriteRenderer>();

            bg.transform.localScale = new Vector3(1, 1, 1);

            var width = bgRenderer.sprite.bounds.size.x;
            var height = bgRenderer.sprite.bounds.size.y;

            float scaleFactor = worldScreenHeight / height;
            float ratio = width / height;

            bg.transform.localScale = new Vector3(scaleFactor, scaleFactor, 1);

            bg.transform.position = new Vector3(transform.position.x - worldScreenWidth / 2 + bgRenderer.bounds.size.x / 2 + totalBGWidth, transform.position.y, 2);
            totalBGWidth += bgRenderer.bounds.size.x;
            swapBGTresholdCameraX = bg.transform.position.x + bgRenderer.bounds.size.x / 2 - worldScreenWidth / 2;
            bgs.Add(bg);
        }
    }

    private void UpdateUI()
    {
        //Counter
        float worldScreenHeight = Camera.main.orthographicSize * 2;
        float worldScreenWidth = worldScreenHeight / Screen.height * Screen.width;
        counter.transform.position = new Vector3(
            transform.position.x + worldScreenWidth / 2,
            transform.position.y + worldScreenHeight / 2 - 3,
            1);
        counter.GetComponentInChildren<TextMeshPro>().SetText(progress.ToString());
        //Tutor
        tutorialText.transform.position = new Vector3(
            transform.position.x,
            transform.position.y + worldScreenHeight / 2 - 4,
            1);
    }

    private void UpdateBG()
    {
        if (bgs.Count > 0)
        {
            //set BG position y
            foreach (var bg in bgs)
            {
                bg.transform.position = new Vector3(bg.transform.position.x, transform.position.y, 2);
            }
            if (transform.position.x >= swapBGTresholdCameraX)
            {
                var lastBg = bgs[bgs.Count - 1];
                var bgRenderer = lastBg.GetComponent<SpriteRenderer>();
                swapBGTresholdCameraX += bgRenderer.bounds.size.x;
                var firstBg = bgs[0];
                firstBg.transform.position = new Vector3(lastBg.transform.position.x + bgRenderer.bounds.size.x, lastBg.transform.position.y, 2);
                bgs.RemoveAt(0);
                bgs.Add(firstBg);
            }
        }
    }

    public void spawnScraper(bool useLastFromPool = true)
    {
        SkyScraper scraper;
        var index = skyScrapers.Count > 0 ? skyScrapers[skyScrapers.Count - 1].index + 1 : 0;
        if (useLastFromPool)
        {
            scraper = skyScrapers[0];
            skyScrapers.RemoveAt(0);
        }
        else
        {
            scraper = Instantiate(skyScraperPrefab);
        }
        scraper.tag = SkyScraper.scraperTag;
        var scraperScaleX = scaleX + UnityEngine.Random.Range(0, scraperWidthDeviation);
        // scraper.transform.localScale = new Vector3(scraperScaleX, scaleY, 1);
        scraper.GetComponent<SpriteRenderer>().drawMode = SpriteDrawMode.Tiled;
        scraper.GetComponent<SpriteRenderer>().size = new Vector2(scraperScaleX, scaleY);
        scraper.GetComponent<BoxCollider2D>().size = scraper.GetComponent<SpriteRenderer>().size;
        var scraperPositionXDelta = initialDeltaBetweenScrapers * UnityEngine.Random.Range(0.38f, scraperDistanceDeviation);
        scraper.transform.position = new Vector3(cityLength + scraperPositionXDelta, -scaleY / 2 + scraperHeight + UnityEngine.Random.Range(0, scraperSizeYDeviation), 1);
        scraper.index = index;
        skyScrapers.Add(scraper);
        cityLength += scraperScaleX + scraperPositionXDelta; // Calculate city length to figure out next scraper pos
    }

    void GenerateGameStart()
    {
        for (int i = 0; i < initialSkyscrapers; i++)
        {
            spawnScraper(false);
        }
        //Put froggo on middle scraper
        var middleScraper = skyScrapers[initialSkyscrapers / 2];
        progressShift = middleScraper.index;
        froggo.transform.position = new Vector3(middleScraper.gameObject.transform.position.x, scraperHeight + scraperSizeYDeviation, 1);
        focusOnFroggo();
    }

    internal void focusOnFroggo()
    {
        this.transform.position = new Vector3(froggo.transform.position.x, froggo.transform.position.y, 0);
        UpdateBG();
        UpdateUI();
    }

    internal IEnumerator gameOverLoadScene(int secs)
    {
        yield return new WaitForSeconds(secs);
        // bannerAd.Hide();
        SceneManager.LoadScene("GameOver");
    }

    internal void gameOver()
    {
        if (!over)
        {
            over = true;

            StartCoroutine(gameOverLoadScene(1));
        }
    }

    internal void OnProgress(int index)
    {
        var newProgress = index - progressShift;
        if (newProgress > progress)
        {
            //For each progress, spawn scraper
            for (var i = progress; i < newProgress; i++)
            {
                spawnScraper();
            }
            progress = newProgress;
            UpdateUI();
        }
    }
}
