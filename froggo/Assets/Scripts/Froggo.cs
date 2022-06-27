using System;
using System.Collections.Generic;
using UnityEngine;

public class Froggo : MonoBehaviour
{
    public AudioClip frogJumpAudio;

    public AudioClip frogDieAudio;

    public AudioClip flyEatenAudio;

    public AudioClip frogLandsAudio;

    public AudioClip frogSpawnAudio;

    public AudioSource audioSource;
    public Sprite frogIdle;

    public Sprite frogJump;
    public int stabilityChecks = 5;

    public int jumpPower = 600;

    public float flyEatenMultiplier = 1.5f;

    public SpriteRenderer spriteRenderer;

    public LineRenderer lineRenderer;
    public Vector3 dragStartPoint;

    bool dragStarted = false;

    public new Rigidbody2D rigidbody;

    public new BoxCollider2D collider;

    public Game game;

    public Vector3 startDragPosition { get; private set; }
    public Vector3 endDragPosition { get; private set; }

    bool onRoof = false;

    int stabilityCheck = 0;

    Vector3 prevPosition = new Vector3(0, 0, 0);

    bool maybeLanded = false;

    int landY = 0;

    private bool flyEaten = false;

    public float jumpMagnitudeMax = 4f;

    private void Awake()
    {
        lineRenderer = GetComponent<LineRenderer>();
        rigidbody = GetComponent<Rigidbody2D>();
        collider = GetComponent<BoxCollider2D>();
        spriteRenderer = GetComponent<SpriteRenderer>();
        audioSource = GetComponent<AudioSource>();
        spriteRenderer.sprite = frogIdle;
        audioSource.clip = frogSpawnAudio;
        Settings.play(audioSource);
        // InvokeRepeating("CheckIfOnRoof", 0, 0.1f);
    }

    public void CheckIfOnRoof()
    {
        if (game.over)
        {
            onRoof = false;
            return;
        }

        if (stabilityCheck == 0)
        {
            prevPosition = transform.position;
        }
        var delta = transform.position - prevPosition;
        if (Math.Abs(delta.x) < 0.5 && Math.Abs(delta.y) < 0.5)
        {
            stabilityCheck++;
            if (stabilityCheck == stabilityChecks)
            {
                stabilityCheck = stabilityChecks - 1;
                if (!onRoof)
                {
                    spriteRenderer.sprite = frogIdle;
                }
                if (!onRoof)
                {
                    audioSource.clip = frogLandsAudio;
                    audioSource.Play();
                }
                onRoof = true;
                // Debug.Log("Frog on roof");
            }
        }
        else
        {
            stabilityCheck = 0;
            if (onRoof)
            {
                spriteRenderer.sprite = frogJump;
            }
            onRoof = false;
            // Debug.Log("Frog not on roof");
        }
    }

    public void HandleWind()
    {
        rigidbody.AddForce(game.wind);
    }

    public void SetStartPoint(Vector3 worldPoint)
    {
        dragStartPoint = worldPoint;
        lineRenderer.SetPosition(0, dragStartPoint);
        lineRenderer.SetPosition(1, dragStartPoint); //Avoid flicker
    }

    public void SetEndPoint(Vector3 worldPoint)
    {
        var endPoint = transform.position + worldPoint - dragStartPoint;
        if (endPoint.x < transform.position.x)
        {
            //Only forward!
            endPoint = new Vector3(transform.position.x, endPoint.y, endPoint.z);
        }
        lineRenderer.SetPosition(1, endPoint);
    }

    void Update()
    {

        if (onRoof)
        {
            var worldPostion = Camera.main.ScreenToWorldPoint(Input.mousePosition) + Vector3.back * -10;
            if (Input.GetMouseButtonDown(0))
            {
                StartDrag(worldPostion);
            }
            else if (Input.GetMouseButton(0) && dragStarted)
            {
                ContinueDrag(worldPostion);
            }
            else if (Input.GetMouseButtonUp(0) && dragStarted)
            {
                StopDrag();
            }
        }
        else
        {
            //Reset line
            lineRenderer.SetPosition(0, new Vector3(0, 0, 0));
            lineRenderer.SetPosition(1, new Vector3(0, 0, 0));
            dragStarted = false;
            game.focusOnFroggo();
        }

        if (this.transform.position.y <= game.pitHeight)
        {
            if (!game.over)
            {
                rigidbody.velocity = new Vector2(0, 0);
                rigidbody.gravityScale = 0.0f;
                audioSource.clip = frogDieAudio;
                Settings.play(audioSource);
                game.gameOver();
            }
        }
    }

    private void StopDrag()
    {

        var direction = endDragPosition - startDragPosition;
        if (direction.x > 0)
        {
            //Only forward!
            direction = new Vector3(0, direction.y, direction.z);
        }
        var forceCoefficient = Math.Min(direction.magnitude / jumpMagnitudeMax, 1); // Because endDragPoint can be below screen
        // Debug.Log("Direction magnitude is " + direction.magnitude + ". Force coef is " + forceCoefficient);
        rigidbody.AddForce(-direction.normalized * jumpPower * forceCoefficient * (flyEaten ? flyEatenMultiplier : 1));
        dragStarted = false;
        flyEaten = false;
        audioSource.clip = frogJumpAudio;
        Settings.play(audioSource);
    }

    private void ContinueDrag(Vector3 worldPostion)
    {
        endDragPosition = worldPostion;
        var direction = endDragPosition - startDragPosition;
        if (direction.magnitude > jumpMagnitudeMax)
        {
            direction = direction.normalized * jumpMagnitudeMax;
        }
        SetEndPoint(transform.position - direction);
    }

    private void StartDrag(Vector3 worldPostion)
    {
        startDragPosition = worldPostion;
        SetStartPoint(transform.position);
        dragStarted = true;
    }

    private void OnCollisionExit2D(Collision2D collision)
    {
        if (collision.gameObject.tag == SkyScraper.scraperTag)
        {
            onRoof = false;
            spriteRenderer.sprite = frogJump;
        }
    }

    private void OnCollisionEnter2D(Collision2D collision)
    {
        if (collision.gameObject.tag == SkyScraper.scraperTag)
        {
            var scraper = collision.gameObject.GetComponent<SkyScraper>();
            Vector3 scraperSize = collision.gameObject.GetComponent<BoxCollider2D>().size;
            // Debug.Log("From landed on " + scraper.index);
            game.OnProgress(scraper.index);

            Vector3 contactPoint = collision.contacts[0].point;
            float bottomFrogY = transform.position.y - collider.size.y / 2;
            float topScraperY = scraper.transform.position.y + scraperSize.y / 2;

            var frogScaperDelta = Math.Round(bottomFrogY) - Math.Round(topScraperY);

            // Debug.Log("FrogScaper delta " + frogScaperDelta);

            if (frogScaperDelta >= 0 && frogScaperDelta <= 1)
            {
                game.tutorialForward();
                onRoof = true;
                spriteRenderer.sprite = frogIdle;
                audioSource.clip = frogLandsAudio;
                Settings.play(audioSource);
            }
            else
            {
                onRoof = false;
                spriteRenderer.sprite = frogJump;
            }
        }

        if (collision.gameObject == game.fly)
        {
            game.flyScript.Die();
            flyEaten = true;
            audioSource.clip = flyEatenAudio;
            Settings.play(audioSource);
        }
    }
}
