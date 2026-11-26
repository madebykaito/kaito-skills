# Delivery profile and platform limits

Preflight enforces Kaito's common delivery profile for every target: MP4 with moov before mdat, 1080x1920 H.264 High, stereo AAC at 48 kHz. This is a deliberately narrower profile than the platforms accept. It checks duration as follows: Instagram 3 to 900 seconds, YouTube Shorts up to 180 seconds, LinkedIn 3 to 900 seconds. Passing is not a guarantee of upload acceptance. Review rights, captions, safe areas and current platform rules before publishing.

- [Instagram Reel publishing specifications](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/content-publishing/#reels-publishing): Reel container, codecs and duration. Platform limits may depend on the publishing API.
- [YouTube Shorts upload](https://support.google.com/youtube/answer/12779649?co=GENIE.Platform%3DDesktop&hl=en): square or vertical, up to three minutes.
- [LinkedIn video requirements](https://www.linkedin.com/help/linkedin/answer/a7494039): desktop duration 3 seconds to 15 minutes, size, resolution, frame rate and bitrate ranges.

The checker does not validate every platform limit, bitrate, frame rate or content rule. Its 48 kHz requirement is Kaito's delivery choice, not a claim that each platform rejects every other sample rate.
