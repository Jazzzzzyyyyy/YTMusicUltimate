#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVKit/AVKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import "../Headers/YTAlertView.h"
#import "../Headers/YTMToastController.h"
#import "../Headers/Localization.h"

typedef NS_ENUM(NSInteger, YTMRepeatMode) {
    YTMRepeatModeOff = 0,
    YTMRepeatModeAll,
    YTMRepeatModeOne
};

@interface YTMDownloads : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *audioFiles;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *label;

// Player
@property (nonatomic, strong) AVPlayer *currentPlayer;
@property (nonatomic, strong) AVPlayerViewController *playerViewController;

// Queue
@property (nonatomic, assign) NSInteger currentPlayingIndex;

// Shuffle
@property (nonatomic, assign) BOOL shuffleEnabled;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *shuffledIndices;
@property (nonatomic, assign) NSInteger currentShufflePosition;

// Repeat
@property (nonatomic, assign) YTMRepeatMode repeatMode;

// Player UI overlay controls
@property (nonatomic, strong) UIImageView *overlayArtworkView;
@property (nonatomic, strong) UILabel *overlayTitleLabel;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *previousButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UIView *controlsOverlay;

// Observers
@property (nonatomic, strong) id timeObserver;
@end
