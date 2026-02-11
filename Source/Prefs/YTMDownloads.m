#import "YTMDownloads.h"

@implementation YTMDownloads

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.currentPlayingIndex = -1;
    self.repeatMode = YTMRepeatModeOff;
    self.shuffleEnabled = NO;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor colorWithRed:3/255.0 green:3/255.0 blue:3/255.0 alpha:1.0];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.tableView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.tableView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.tableView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor]
    ]];

    [self maybeShowEmptyState];
    [self refreshAudioFiles];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:@"ReloadDataNotification" object:nil];
}

- (void)maybeShowEmptyState {
    if (self.audioFiles.count == 0) {
        self.imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"yt_outline_audio_48pt" inBundle:[NSBundle mainBundle] compatibleWithTraitCollection:nil]];
        self.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.imageView.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
        self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.tableView addSubview:self.imageView];

        self.label = [[UILabel alloc] initWithFrame:CGRectZero];
        self.label.text = LOC(@"EMPTY");
        self.label.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
        self.label.numberOfLines = 0;
        self.label.font = [UIFont systemFontOfSize:16];
        self.label.textAlignment = NSTextAlignmentCenter;
        self.label.translatesAutoresizingMaskIntoConstraints = NO;
        [self.label sizeToFit];
        [self.tableView addSubview:self.label];

        [NSLayoutConstraint activateConstraints:@[
            [self.imageView.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
            [self.imageView.bottomAnchor constraintEqualToAnchor:self.tableView.centerYAnchor constant:-30],
            [self.imageView.widthAnchor constraintEqualToConstant:48],
            [self.imageView.heightAnchor constraintEqualToConstant:48],

            [self.label.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
            [self.label.topAnchor constraintEqualToAnchor:self.imageView.bottomAnchor constant:20],
            [self.label.leadingAnchor constraintEqualToAnchor:self.tableView.leadingAnchor constant:20],
            [self.label.trailingAnchor constraintEqualToAnchor:self.tableView.trailingAnchor constant:-20],
        ]];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.currentPlayer && self.timeObserver) {
        [self.currentPlayer removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
    [self cleanupRemoteCommandCenter];
}

- (void)cleanupRemoteCommandCenter {
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand removeTarget:self];
    [commandCenter.pauseCommand removeTarget:self];
    [commandCenter.togglePlayPauseCommand removeTarget:self];
    [commandCenter.nextTrackCommand removeTarget:self];
    [commandCenter.previousTrackCommand removeTarget:self];
    [commandCenter.changePlaybackPositionCommand removeTarget:self];
}

#pragma mark - Data

- (void)reloadData {
    [self refreshAudioFiles];
    [self.tableView reloadData];
}

- (void)refreshAudioFiles {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *downloadsURL = [documentsURL URLByAppendingPathComponent:@"YTMusicUltimate"];

    NSError *error;
    NSArray *allFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:downloadsURL.path error:&error];

    if (error) {
        NSLog(@"Error reading contents of directory: %@", error.localizedDescription);
        return;
    }

    NSPredicate *m4aPredicate = [NSPredicate predicateWithFormat:@"SELF ENDSWITH[c] '.m4a'"];
    NSPredicate *mp3Predicate = [NSPredicate predicateWithFormat:@"SELF ENDSWITH[c] '.mp3'"];
    NSPredicate *predicate = [NSCompoundPredicate orPredicateWithSubpredicates:@[m4aPredicate, mp3Predicate]];

    self.audioFiles = [NSMutableArray arrayWithArray:[allFiles filteredArrayUsingPredicate:predicate]];

    self.imageView.tintColor = self.audioFiles.count == 0 ? [[UIColor whiteColor] colorWithAlphaComponent:0.8] : [UIColor clearColor];
    self.label.textColor = self.audioFiles.count == 0 ? [[UIColor whiteColor] colorWithAlphaComponent:0.8] : [UIColor clearColor];
}

#pragma mark - Helper: Documents path and artwork

- (NSURL *)downloadsDirectoryURL {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    return [documentsURL URLByAppendingPathComponent:@"YTMusicUltimate"];
}

- (UIImage *)artworkImageForIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.audioFiles.count) return nil;
    NSString *imageName = [NSString stringWithFormat:@"%@.png", [self.audioFiles[index] stringByDeletingPathExtension]];
    NSString *documentsDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    return [UIImage imageWithContentsOfFile:[[documentsDirectory stringByAppendingPathComponent:@"YTMusicUltimate"] stringByAppendingPathComponent:imageName]];
}

- (NSString *)songTitleForIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.audioFiles.count) return @"";
    return [self.audioFiles[index] stringByDeletingPathExtension];
}

#pragma mark - Queue Management

- (void)generateShuffledIndicesFromIndex:(NSInteger)startIndex {
    NSMutableArray<NSNumber *> *indices = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)self.audioFiles.count; i++) {
        if (i != startIndex) {
            [indices addObject:@(i)];
        }
    }
    // Fisher-Yates shuffle
    for (NSInteger i = indices.count - 1; i > 0; i--) {
        NSInteger j = arc4random_uniform((uint32_t)(i + 1));
        [indices exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    // Put the current song first
    [indices insertObject:@(startIndex) atIndex:0];
    self.shuffledIndices = indices;
    self.currentShufflePosition = 0;
}

#pragma mark - Playback

- (void)playTrackAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.audioFiles.count) return;

    self.currentPlayingIndex = index;

    NSURL *audioURL = [[self downloadsDirectoryURL] URLByAppendingPathComponent:self.audioFiles[index]];
    NSString *titleString = [self songTitleForIndex:index];
    UIImage *artworkImage = [self artworkImageForIndex:index];

    // Audio session
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
    [audioSession setActive:YES error:nil];

    // Create player item
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:audioURL];

    // Set external metadata
    NSMutableArray *metadataItems = [NSMutableArray array];

    AVMutableMetadataItem *titleMetadataItem = [AVMutableMetadataItem metadataItem];
    titleMetadataItem.key = AVMetadataCommonKeyTitle;
    titleMetadataItem.keySpace = AVMetadataKeySpaceCommon;
    titleMetadataItem.value = titleString;
    [metadataItems addObject:titleMetadataItem];

    if (artworkImage) {
        AVMutableMetadataItem *artworkMetadataItem = [AVMutableMetadataItem metadataItem];
        artworkMetadataItem.key = AVMetadataCommonKeyArtwork;
        artworkMetadataItem.keySpace = AVMetadataKeySpaceCommon;
        artworkMetadataItem.value = UIImagePNGRepresentation(artworkImage);
        [metadataItems addObject:artworkMetadataItem];
    }

    playerItem.externalMetadata = metadataItems;

    // Remove old observer
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];

    if (!self.currentPlayer) {
        self.currentPlayer = [AVPlayer playerWithPlayerItem:playerItem];
    } else {
        [self.currentPlayer replaceCurrentItemWithPlayerItem:playerItem];
    }

    // Observe end of track
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:playerItem];

    // Setup now playing info and remote commands
    [self setupNowPlayingInfoForIndex:index];
    [self setupRemoteCommandCenter];
    [self setupTimeObserver];

    // Present player UI if not already presented
    if (!self.playerViewController || !self.playerViewController.presentingViewController) {
        self.playerViewController = [[AVPlayerViewController alloc] init];
        self.playerViewController.player = self.currentPlayer;
        [self setupControlsOverlayOnPlayerViewController];

        [self presentViewController:self.playerViewController animated:YES completion:^{
            [self.currentPlayer play];
            [self updatePlayPauseButton];
        }];
    } else {
        self.playerViewController.player = self.currentPlayer;
        [self.currentPlayer play];
        [self updateOverlayForCurrentTrack];
        [self updatePlayPauseButton];
    }

    // Highlight in table
    [self.tableView reloadData];
    NSIndexPath *ip = [NSIndexPath indexPathForRow:index inSection:0];
    if (index < (NSInteger)self.audioFiles.count) {
        [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    switch (self.repeatMode) {
        case YTMRepeatModeOne: {
            [self.currentPlayer seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
                [self.currentPlayer play];
            }];
            break;
        }
        case YTMRepeatModeAll: {
            [self advanceToNextTrack:YES];
            break;
        }
        case YTMRepeatModeOff:
        default: {
            [self advanceToNextTrack:NO];
            break;
        }
    }
}

- (void)advanceToNextTrack:(BOOL)wrapAround {
    NSInteger nextIndex = -1;

    if (self.shuffleEnabled && self.shuffledIndices.count > 0) {
        NSInteger nextPos = self.currentShufflePosition + 1;
        if (nextPos < (NSInteger)self.shuffledIndices.count) {
            self.currentShufflePosition = nextPos;
            nextIndex = [self.shuffledIndices[nextPos] integerValue];
        } else if (wrapAround) {
            self.currentShufflePosition = 0;
            nextIndex = [self.shuffledIndices[0] integerValue];
        }
    } else {
        NSInteger nextPos = self.currentPlayingIndex + 1;
        if (nextPos < (NSInteger)self.audioFiles.count) {
            nextIndex = nextPos;
        } else if (wrapAround) {
            nextIndex = 0;
        }
    }

    if (nextIndex >= 0) {
        [self playTrackAtIndex:nextIndex];
    }
}

- (void)goToPreviousTrack {
    NSInteger prevIndex = -1;

    if (self.shuffleEnabled && self.shuffledIndices.count > 0) {
        NSInteger prevPos = self.currentShufflePosition - 1;
        if (prevPos >= 0) {
            self.currentShufflePosition = prevPos;
            prevIndex = [self.shuffledIndices[prevPos] integerValue];
        } else if (self.repeatMode == YTMRepeatModeAll) {
            self.currentShufflePosition = (NSInteger)self.shuffledIndices.count - 1;
            prevIndex = [self.shuffledIndices[self.currentShufflePosition] integerValue];
        }
    } else {
        NSInteger prevPos = self.currentPlayingIndex - 1;
        if (prevPos >= 0) {
            prevIndex = prevPos;
        } else if (self.repeatMode == YTMRepeatModeAll) {
            prevIndex = (NSInteger)self.audioFiles.count - 1;
        }
    }

    if (prevIndex >= 0) {
        [self playTrackAtIndex:prevIndex];
    }
}

#pragma mark - Now Playing Info Center

- (void)setupNowPlayingInfoForIndex:(NSInteger)index {
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];
    nowPlayingInfo[MPMediaItemPropertyTitle] = [self songTitleForIndex:index];

    UIImage *artworkImage = [self artworkImageForIndex:index];
    if (artworkImage) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artworkImage.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return artworkImage;
        }];
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork;
    }

    AVPlayerItem *item = self.currentPlayer.currentItem;
    if (item) {
        CMTime duration = item.asset.duration;
        if (CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration)) {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = @(CMTimeGetSeconds(duration));
        }
    }
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(CMTimeGetSeconds(self.currentPlayer.currentTime));
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(self.currentPlayer.rate);

    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
}

- (void)updateNowPlayingElapsedTime {
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionaryWithDictionary:[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo ?: @{}];
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(CMTimeGetSeconds(self.currentPlayer.currentTime));
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(self.currentPlayer.rate);
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
}

#pragma mark - Remote Command Center

- (void)setupRemoteCommandCenter {
    [self cleanupRemoteCommandCenter];

    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];

    [commandCenter.playCommand addTarget:self action:@selector(remotePlay:)];
    [commandCenter.pauseCommand addTarget:self action:@selector(remotePause:)];
    [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(remoteTogglePlayPause:)];
    [commandCenter.nextTrackCommand addTarget:self action:@selector(remoteNextTrack:)];
    [commandCenter.previousTrackCommand addTarget:self action:@selector(remotePreviousTrack:)];
    [commandCenter.changePlaybackPositionCommand addTarget:self action:@selector(remoteChangePlaybackPosition:)];

    commandCenter.playCommand.enabled = YES;
    commandCenter.pauseCommand.enabled = YES;
    commandCenter.togglePlayPauseCommand.enabled = YES;
    commandCenter.nextTrackCommand.enabled = YES;
    commandCenter.previousTrackCommand.enabled = YES;
    commandCenter.changePlaybackPositionCommand.enabled = YES;
}

- (MPRemoteCommandHandlerStatus)remotePlay:(MPRemoteCommandEvent *)event {
    [self.currentPlayer play];
    [self updatePlayPauseButton];
    [self updateNowPlayingElapsedTime];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remotePause:(MPRemoteCommandEvent *)event {
    [self.currentPlayer pause];
    [self updatePlayPauseButton];
    [self updateNowPlayingElapsedTime];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remoteTogglePlayPause:(MPRemoteCommandEvent *)event {
    if (self.currentPlayer.rate > 0) {
        [self.currentPlayer pause];
    } else {
        [self.currentPlayer play];
    }
    [self updatePlayPauseButton];
    [self updateNowPlayingElapsedTime];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remoteNextTrack:(MPRemoteCommandEvent *)event {
    BOOL wrapAround = (self.repeatMode == YTMRepeatModeAll);
    [self advanceToNextTrack:wrapAround];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remotePreviousTrack:(MPRemoteCommandEvent *)event {
    [self goToPreviousTrack];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remoteChangePlaybackPosition:(MPChangePlaybackPositionCommandEvent *)event {
    CMTime seekTime = CMTimeMakeWithSeconds(event.positionTime, NSEC_PER_SEC);
    [self.currentPlayer seekToTime:seekTime completionHandler:^(BOOL finished) {
        [self updateNowPlayingElapsedTime];
    }];
    return MPRemoteCommandHandlerStatusSuccess;
}

#pragma mark - Time Observer

- (void)setupTimeObserver {
    if (self.timeObserver) {
        [self.currentPlayer removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.currentPlayer addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1.0, NSEC_PER_SEC)
                                                                        queue:dispatch_get_main_queue()
                                                                   usingBlock:^(CMTime time) {
        [weakSelf updateNowPlayingElapsedTime];
    }];
}

#pragma mark - Custom Player UI Overlay

- (void)setupControlsOverlayOnPlayerViewController {
    UIView *overlay = self.playerViewController.contentOverlayView;
    if (!overlay) return;

    // Semi-transparent dark background
    self.controlsOverlay = [[UIView alloc] init];
    self.controlsOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    self.controlsOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    self.controlsOverlay.layer.cornerRadius = 20;
    [overlay addSubview:self.controlsOverlay];

    // Album art
    self.overlayArtworkView = [[UIImageView alloc] init];
    self.overlayArtworkView.translatesAutoresizingMaskIntoConstraints = NO;
    self.overlayArtworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.overlayArtworkView.clipsToBounds = YES;
    self.overlayArtworkView.layer.cornerRadius = 12;
    [self.controlsOverlay addSubview:self.overlayArtworkView];

    // Title
    self.overlayTitleLabel = [[UILabel alloc] init];
    self.overlayTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.overlayTitleLabel.textColor = [UIColor whiteColor];
    self.overlayTitleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.overlayTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.overlayTitleLabel.numberOfLines = 2;
    [self.controlsOverlay addSubview:self.overlayTitleLabel];

    // Transport controls
    UIColor *buttonColor = [UIColor whiteColor];
    UIColor *accentColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];

    UIImageSymbolConfiguration *transportConfig = [UIImageSymbolConfiguration configurationWithPointSize:36 weight:UIImageSymbolWeightMedium];
    UIImageSymbolConfiguration *secondaryConfig = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];

    self.previousButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.previousButton setImage:[[UIImage systemImageNamed:@"backward.fill" withConfiguration:transportConfig] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    self.previousButton.tintColor = buttonColor;
    self.previousButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.previousButton addTarget:self action:@selector(previousButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    self.playPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.playPauseButton setImage:[[UIImage systemImageNamed:@"play.fill" withConfiguration:transportConfig] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    self.playPauseButton.tintColor = buttonColor;
    self.playPauseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.playPauseButton addTarget:self action:@selector(playPauseButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    self.nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.nextButton setImage:[[UIImage systemImageNamed:@"forward.fill" withConfiguration:transportConfig] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    self.nextButton.tintColor = buttonColor;
    self.nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.nextButton addTarget:self action:@selector(nextButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    // Secondary controls
    self.shuffleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.shuffleButton setImage:[[UIImage systemImageNamed:@"shuffle" withConfiguration:secondaryConfig] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    self.shuffleButton.tintColor = self.shuffleEnabled ? accentColor : buttonColor;
    self.shuffleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.shuffleButton addTarget:self action:@selector(shuffleButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    self.repeatButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self updateRepeatButtonIcon];
    self.repeatButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.repeatButton addTarget:self action:@selector(repeatButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    // Transport stack
    UIStackView *transportStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.previousButton, self.playPauseButton, self.nextButton]];
    transportStack.axis = UILayoutConstraintAxisHorizontal;
    transportStack.distribution = UIStackViewDistributionEqualSpacing;
    transportStack.alignment = UIStackViewAlignmentCenter;
    transportStack.spacing = 40;
    transportStack.translatesAutoresizingMaskIntoConstraints = NO;

    // Secondary stack
    UIStackView *secondaryStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.shuffleButton, self.repeatButton]];
    secondaryStack.axis = UILayoutConstraintAxisHorizontal;
    secondaryStack.distribution = UIStackViewDistributionEqualSpacing;
    secondaryStack.alignment = UIStackViewAlignmentCenter;
    secondaryStack.spacing = 60;
    secondaryStack.translatesAutoresizingMaskIntoConstraints = NO;

    [self.controlsOverlay addSubview:transportStack];
    [self.controlsOverlay addSubview:secondaryStack];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.controlsOverlay.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:16],
        [self.controlsOverlay.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-16],
        [self.controlsOverlay.topAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.topAnchor constant:16],
        [self.controlsOverlay.bottomAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.bottomAnchor constant:-16],

        [self.overlayArtworkView.topAnchor constraintEqualToAnchor:self.controlsOverlay.topAnchor constant:30],
        [self.overlayArtworkView.centerXAnchor constraintEqualToAnchor:self.controlsOverlay.centerXAnchor],
        [self.overlayArtworkView.widthAnchor constraintEqualToConstant:250],
        [self.overlayArtworkView.heightAnchor constraintEqualToConstant:250],

        [self.overlayTitleLabel.topAnchor constraintEqualToAnchor:self.overlayArtworkView.bottomAnchor constant:24],
        [self.overlayTitleLabel.leadingAnchor constraintEqualToAnchor:self.controlsOverlay.leadingAnchor constant:20],
        [self.overlayTitleLabel.trailingAnchor constraintEqualToAnchor:self.controlsOverlay.trailingAnchor constant:-20],

        [transportStack.topAnchor constraintEqualToAnchor:self.overlayTitleLabel.bottomAnchor constant:30],
        [transportStack.centerXAnchor constraintEqualToAnchor:self.controlsOverlay.centerXAnchor],

        [secondaryStack.topAnchor constraintEqualToAnchor:transportStack.bottomAnchor constant:30],
        [secondaryStack.centerXAnchor constraintEqualToAnchor:self.controlsOverlay.centerXAnchor],
    ]];

    [self updateOverlayForCurrentTrack];
}

- (void)updateOverlayForCurrentTrack {
    if (self.currentPlayingIndex < 0 || self.currentPlayingIndex >= (NSInteger)self.audioFiles.count) return;
    self.overlayArtworkView.image = [self artworkImageForIndex:self.currentPlayingIndex];
    self.overlayTitleLabel.text = [self songTitleForIndex:self.currentPlayingIndex];
}

- (void)updatePlayPauseButton {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:36 weight:UIImageSymbolWeightMedium];
    NSString *iconName = (self.currentPlayer.rate > 0) ? @"pause.fill" : @"play.fill";
    [self.playPauseButton setImage:[[UIImage systemImageNamed:iconName withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
}

- (void)updateRepeatButtonIcon {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    UIColor *accentColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
    UIColor *buttonColor = [UIColor whiteColor];

    NSString *iconName;
    UIColor *tint;
    switch (self.repeatMode) {
        case YTMRepeatModeAll:
            iconName = @"repeat";
            tint = accentColor;
            break;
        case YTMRepeatModeOne:
            iconName = @"repeat.1";
            tint = accentColor;
            break;
        case YTMRepeatModeOff:
        default:
            iconName = @"repeat";
            tint = buttonColor;
            break;
    }
    [self.repeatButton setImage:[[UIImage systemImageNamed:iconName withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    self.repeatButton.tintColor = tint;
}

#pragma mark - Button Actions

- (void)playPauseButtonTapped {
    if (self.currentPlayer.rate > 0) {
        [self.currentPlayer pause];
    } else {
        [self.currentPlayer play];
    }
    [self updatePlayPauseButton];
    [self updateNowPlayingElapsedTime];
}

- (void)previousButtonTapped {
    [self goToPreviousTrack];
}

- (void)nextButtonTapped {
    BOOL wrapAround = (self.repeatMode == YTMRepeatModeAll);
    [self advanceToNextTrack:wrapAround];
}

- (void)shuffleButtonTapped {
    UIColor *accentColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
    self.shuffleEnabled = !self.shuffleEnabled;
    self.shuffleButton.tintColor = self.shuffleEnabled ? accentColor : [UIColor whiteColor];

    if (self.shuffleEnabled && self.currentPlayingIndex >= 0) {
        [self generateShuffledIndicesFromIndex:self.currentPlayingIndex];
    }
}

- (void)repeatButtonTapped {
    switch (self.repeatMode) {
        case YTMRepeatModeOff:
            self.repeatMode = YTMRepeatModeAll;
            break;
        case YTMRepeatModeAll:
            self.repeatMode = YTMRepeatModeOne;
            break;
        case YTMRepeatModeOne:
            self.repeatMode = YTMRepeatModeOff;
            break;
    }
    [self updateRepeatButtonIcon];
}

#pragma mark - Table view stuff
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"\n\n" : nil; //Temporary, see YTMTab.x
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 1 ? @"\n\n\n" : nil; //Temporary, see YTMTab.x
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && self.audioFiles.count == 0) {
        return 0;
    }
    return UITableViewAutomaticDimension;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.audioFiles.count;
    }

    if (section == 1) {
        return 2;
    }

    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    }

    if (indexPath.section == 0 && indexPath.row < (NSInteger)self.audioFiles.count) {
        cell.textLabel.text = [self.audioFiles[indexPath.row] stringByDeletingPathExtension];
        cell.textLabel.numberOfLines = 0;

        // Highlight currently playing song
        if (indexPath.row == self.currentPlayingIndex) {
            cell.backgroundColor = [[UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0] colorWithAlphaComponent:0.3];
            cell.textLabel.textColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
        } else {
            cell.backgroundColor = [[UIColor grayColor] colorWithAlphaComponent:0.25];
            cell.textLabel.textColor = [UIColor whiteColor];
        }

        NSString *imageName = [NSString stringWithFormat:@"%@.png", [self.audioFiles[indexPath.row] stringByDeletingPathExtension]];
        NSString *documentsDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];

        UIImage *image = [UIImage imageWithContentsOfFile:[[documentsDirectory stringByAppendingPathComponent:@"YTMusicUltimate"] stringByAppendingPathComponent:imageName]];
        CGFloat targetSize = 37.5;
        CGFloat scaleFactor = targetSize / MAX(image.size.width, image.size.height);
        CGSize scaledSize = CGSizeMake(image.size.width * scaleFactor, image.size.height * scaleFactor);
        UIGraphicsBeginImageContextWithOptions(scaledSize, NO, 0.0);
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, scaledSize.width, scaledSize.height) cornerRadius:6] addClip];
        [image drawInRect:CGRectMake(0, 0, scaledSize.width, scaledSize.height)];
        UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        roundedImage = [roundedImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        cell.imageView.image = roundedImage;
    }

    else if (indexPath.section == 1) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell0"];
        NSArray *settingsData = @[
            @{@"title": LOC(@"SHARE_ALL"), @"icon": @"square.and.arrow.up.on.square"},
            @{@"title": LOC(@"REMOVE_ALL"), @"icon": @"trash"},
        ];

        NSDictionary *data = settingsData[indexPath.row];

        cell.textLabel.text = data[@"title"];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.adjustsFontSizeToFitWidth = YES;
        cell.imageView.image = [UIImage systemImageNamed:data[@"icon"]];
        cell.imageView.tintColor = indexPath.row == 1 ? [UIColor redColor] : [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
        cell.backgroundColor = [[UIColor grayColor] colorWithAlphaComponent:0.25];
    }

    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UIContextualAction *shareAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            [self showActivityViewControllerForIndexPath:indexPath];
            completionHandler(YES);
        }];
        shareAction.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
        shareAction.backgroundColor = [UIColor systemBlueColor];

        UIContextualAction *renameAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            [self renameFileForIndexPath:indexPath];
            completionHandler(YES);
        }];
        renameAction.image = [UIImage systemImageNamed:@"pencil"];
        renameAction.backgroundColor = [UIColor systemOrangeColor];

        UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            [self deleteFileForIndexPath:indexPath];
            completionHandler(YES);
        }];
        deleteAction.image = [UIImage systemImageNamed:@"trash"];

        UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, renameAction, shareAction]];
        configuration.performsFirstActionWithFullSwipe = YES;

        return configuration;
    } else {
        return nil;
    }
}

- (void)showActivityViewControllerForIndexPath:(NSIndexPath *)indexPath {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *audioURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@", self.audioFiles[indexPath.row]]];

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[audioURL] applicationActivities:nil];
    activityViewController.excludedActivityTypes = @[UIActivityTypeAssignToContact, UIActivityTypePrint];

    [self presentViewController:activityViewController animated:YES completion:nil];
}

- (void)renameFileForIndexPath:(NSIndexPath *)indexPath {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *audioURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@", self.audioFiles[indexPath.row]]];
    NSURL *coverURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@.png", [self.audioFiles[indexPath.row] stringByDeletingPathExtension]]];

    UITextView *textView = [[UITextView alloc] init];
    textView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.15];
    textView.layer.cornerRadius = 3.0;
    textView.layer.borderWidth = 1.0;
    textView.layer.borderColor = [[UIColor grayColor] colorWithAlphaComponent:0.5].CGColor;
    textView.textColor = [UIColor whiteColor];
    textView.text = [self.audioFiles[indexPath.row] stringByDeletingPathExtension];
    textView.editable = YES;
    textView.scrollEnabled = YES;
    textView.textAlignment = NSTextAlignmentNatural;
    textView.font = [UIFont systemFontOfSize:14.0];

    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        NSString *newName = [textView.text stringByReplacingOccurrencesOfString:@"/" withString:@""];
        NSString *extension = [audioURL pathExtension];

        NSURL *newAudioURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@.%@", newName, extension]];
        NSURL *newCoverURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@.png", newName]];

        NSError *error = nil;
        [[NSFileManager defaultManager] moveItemAtURL:audioURL toURL:newAudioURL error:&error];
        [[NSFileManager defaultManager] moveItemAtURL:coverURL toURL:newCoverURL error:&error];

        if (!error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self reloadData];
                [[NSClassFromString(@"YTMToastController") alloc] showMessage:LOC(@"DONE")];
            });
        }
    }
    actionTitle:LOC(@"RENAME")];
    alertView.title = @"YTMusicUltimate";

    UIView *customView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, alertView.frameForDialog.size.width - 50, 75)];
    textView.frame = customView.frame;
    [customView addSubview:textView];

    alertView.customContentView = customView;
    [alertView show];
}

- (void)deleteFileForIndexPath:(NSIndexPath *)indexPath {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *audioURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@", self.audioFiles[indexPath.row]]];
    NSURL *coverURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@.png", [self.audioFiles[indexPath.row] stringByDeletingPathExtension]]];

    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        BOOL audioRemoved = [[NSFileManager defaultManager] removeItemAtURL:audioURL error:nil];
        BOOL coverRemoved = [[NSFileManager defaultManager] removeItemAtURL:coverURL error:nil];

        if (audioRemoved && coverRemoved) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.audioFiles removeObjectAtIndex:indexPath.row];
                [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                [self maybeShowEmptyState];
            });
        }
    }
    actionTitle:LOC(@"DELETE")];
    alertView.title = @"YTMusicUltimate";
    alertView.subtitle = [NSString stringWithFormat:LOC(@"DELETE_MESSAGE"), [self.audioFiles[indexPath.row] stringByDeletingPathExtension]];
    [alertView show];
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        NSInteger tappedIndex = indexPath.row;

        if (self.shuffleEnabled) {
            [self generateShuffledIndicesFromIndex:tappedIndex];
        }

        [self playTrackAtIndex:tappedIndex];
    }

    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            [self shareAll];
        }

        if (indexPath.row == 1) {
            [self removeAll];
        }
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)shareAll {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *audiosFolder = [documentsURL URLByAppendingPathComponent:@"YTMusicUltimate"];

    NSArray<NSURL *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:audiosFolder
                                                               includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    error:nil];

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"pathExtension.lowercaseString == 'm4a' || pathExtension.lowercaseString == 'mp3'"];
    files = [files filteredArrayUsingPredicate:predicate];

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
    activityViewController.excludedActivityTypes = @[UIActivityTypeAssignToContact, UIActivityTypePrint];

    [self presentViewController:activityViewController animated:YES completion:nil];
}

- (void)removeAll {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *audiosFolder = [documentsURL URLByAppendingPathComponent:@"YTMusicUltimate"];

    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        BOOL audiosRemoved = [[NSFileManager defaultManager] removeItemAtURL:audiosFolder error:nil];

        if (audiosRemoved) {
            [self.audioFiles removeAllObjects];
            self.currentPlayingIndex = -1;
            self.imageView.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
            self.label.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
        }
    }
    actionTitle:LOC(@"DELETE")];
    alertView.title = @"YTMusicUltimate";
    alertView.subtitle = [NSString stringWithFormat:LOC(@"DELETE_MESSAGE"), LOC(@"ALL_DOWNLOADS")];
    [alertView show];
}

@end
