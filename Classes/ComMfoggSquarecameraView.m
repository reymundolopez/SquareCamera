
// original via github.com/mikefogg/SquareCamera

// Modifications / Attempts to fix using ramdom bit of code found here and there : Kosso : August 2013

#import "ComMfoggSquarecameraView.h"
#import "ComMfoggSquarecameraViewProxy.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreMedia/CoreMedia.h>



@implementation ComMfoggSquarecameraView

// used for KVO observation of the @"capturingStillImage" property to perform flash bulb animation
static const NSString *AVCaptureStillImageIsCapturingStillImageContext = @"AVCaptureStillImageIsCapturingStillImageContext";

#pragma mark - Lifetime
-(void)initializeState
{
	[super initializeState];
    
    [self setPrevLayer:nil];
    [self setStillImage:nil];
    [self setStillImageOutput:nil];
    [self setCaptureDevice:nil];
    
    // Set defaults
    self.camera = @"back"; // Default camera is 'back'
}



- (void) dealloc
{
    NSLog(@"[INFO]  --------------------- dealloc has been called");
	[self teardownAVCapture];

    [self setPrevLayer:nil];
    [self setStillImage:nil];
    [self setStillImageOutput:nil];
    [self setCaptureDevice:nil];
    [self setCamera:nil];

    RELEASE_TO_NIL(flashView);
	RELEASE_TO_NIL(square);

    NSLog(@"[INFO] ---------------------  Self : %@", self);
	[super dealloc];
}


-(void)frameSizeChanged:(CGRect)frame bounds:(CGRect)bounds
{
    // This is initializing the square view
  	[TiUtils setView:self.square positionRect:bounds];
}

#pragma mark - Actions
- (void)turnFlashOn:(id)args
{
	if([self.captureDevice lockForConfiguration:true]){
        if([self.captureDevice isFlashModeSupported:AVCaptureFlashModeOn]){
            [self.captureDevice setFlashMode:AVCaptureFlashModeOn];
            self.flashOn = YES;
            [self.captureDevice lockForConfiguration:false];
            
            [self.proxy fireEvent:@"onFlashOn"];
        };
    };
};

- (void)turnFlashOff:(id)args
{
	if([self.captureDevice lockForConfiguration:true]){
        if([self.captureDevice isFlashModeSupported:AVCaptureFlashModeOn]){
            [self.captureDevice setFlashMode:AVCaptureFlashModeOff];
            self.flashOn = NO;  
            [self.captureDevice lockForConfiguration:false];

            [self.proxy fireEvent:@"onFlashOff"];
        };
	};
};



- (void)takePhoto:(id)args
{

	AVCaptureConnection *stillImageConnection = nil;

	for (AVCaptureConnection *connection in self.stillImageOutput.connections)
	{
		for (AVCaptureInputPort *port in [connection inputPorts])
		{
			if ([[port mediaType] isEqual:AVMediaTypeVideo] )
			{
				stillImageConnection = connection;
				break;
			}
		}
		if (stillImageConnection) { break; }
	}

	UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];

	[self.stillImageOutput captureStillImageAsynchronouslyFromConnection:stillImageConnection completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error)
	{ 

		CFDictionaryRef exifAttachments = CMGetAttachment(imageSampleBuffer, kCGImagePropertyExifDictionary, NULL);
		if (exifAttachments) {
			NSLog(@"[INFO] imageSampleBuffer Exif attachments: %@", exifAttachments);
		} else { 
			NSLog(@"[INFO] No imageSampleBuffer Exif attachments");
		}

		NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];    

		UIImage *image = [[UIImage alloc] initWithData:imageData];

          CGSize size = image.size;  // this will be the full size of the screen 

          NSLog(@"image.size : %@", NSStringFromCGSize(size));

          CGFloat image_width = self.stillImage.frame.size.width*2;
          CGFloat image_height = self.stillImage.frame.size.height*2;

          CGRect cropRect = CGRectMake(
          	0,
          	0,
          	image_width,
          	image_height
          	);

          NSLog(@"cropRect : %@", NSStringFromCGRect(cropRect));


          CGRect customImageRect = CGRectMake(
          	-((((cropRect.size.width/size.width)*size.height)-cropRect.size.height)/2),
          	0,
          	((cropRect.size.width/size.width)*size.height),
          	cropRect.size.width);
          
          UIGraphicsBeginImageContext(cropRect.size);
          CGContextRef context = UIGraphicsGetCurrentContext();  
          
          CGContextScaleCTM(context, 1.0, -1.0);  
          CGContextRotateCTM(context, -M_PI/2);  
          
          CGContextDrawImage(context, customImageRect,
          	image.CGImage);
          
          UIImage *croppedImage = UIGraphicsGetImageFromCurrentImageContext();  
          UIGraphicsEndImageContext();          
          
          TiBlob *imageBlob = [[TiBlob alloc] initWithImage:[self flipImage:croppedImage]]; // maybe try image here 
          NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
																self.camera, @"camera",
																imageBlob, @"media",
																nil];
          
          // HURRAH! 
          [self.proxy fireEvent:@"success" withObject:event];

        }];
}

-(UIImage *)flipImage:(UIImage *)img
{
	UIImage* flippedImage = img;

	if([self.camera isEqualToString: @"front"]){
  	flippedImage = [UIImage imageWithCGImage:img.CGImage scale:img.scale orientation:(img.imageOrientation + 4) % 8];
  };

  return flippedImage;
}


-(void)pause:(id)args
{
    if(self.captureSession){
        if([self.captureSession isRunning]){
            [self.captureSession stopRunning];
            
            NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"paused", @"state",
                                   nil];
            
            [self.proxy fireEvent:@"stateChange" withObject:event];

        } else {
            NSLog(@"[ERROR] Attempted to pause an already paused session... ignoring.");
        };
    } else {
        NSLog(@"[ERROR] Attempted to pause the camera before it was started... ignoring.");
    };
};

-(void)resume:(id)args
{
    if(self.captureSession){
        if(![self.captureSession isRunning]){
            [self.captureSession startRunning];
            
            NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"resumed", @"state",
                                   nil];
            
            [self.proxy fireEvent:@"stateChange" withObject:event];

        } else {
            NSLog(@"[ERROR] Attempted to resume an already running session... ignoring.");
        };
    } else {
        NSLog(@"[ERROR] Attempted to resume the camera before it was started... ignoring.");
    };
};

#pragma mark - Configurations
//-(void)setCamera_:(id)value
//{
//    NSLog(@"[INFO] --------------------- --------------------- --------------------- setCamera is called");
//	NSString *camera = [TiUtils stringValue:value];
//    
//	if (![camera isEqualToString: @"front"] && ![camera isEqualToString: @"back"]) {
//		NSLog(@"[ERROR] Attempted to set camera that is not front or back... ignoring.");
//	} else {
//		self.camera = camera;
//        
//		[self setCaptureDevice];
//        
//		NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
//                               self.camera, @"camera",
//                               nil];
//        
//		[self.proxy fireEvent:@"onCameraChange" withObject:event];
//	}
//}


// utility routine to display error alert if takePicture fails
- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message
{
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%d)", message, (int)[error code]]
                                                            message:[error localizedDescription]
                                                           delegate:nil
                                                  cancelButtonTitle:@"Dismiss" 
                                                  otherButtonTitles:nil];
		[alertView show];
		[alertView release];
	});
}

-(void)setCaptureDevice
{
    NSLog(@"[INFO] --------------------- --------------------- setCaptureDevice is called");
    
	AVCaptureDevicePosition desiredPosition;
	
	if ([self.camera isEqualToString: @"back"]){
		desiredPosition = AVCaptureDevicePositionBack;

		if([self.captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080] == YES)
		{
			self.captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
		} else {
			self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
		}

	} else {
		desiredPosition = AVCaptureDevicePositionFront;
		self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
	};
    
    
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
		if ([device position] == desiredPosition) {
//            [[self captureSession] beginConfiguration];
            
            NSError *error = nil;
			AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
            
            NSLog(@"[INFO] --------------------- Input : %@", input);
            NSLog(@"[INFO] --------------------- Error : %@", error);
            NSLog(@"[INFO] --------------------- device : %@", device);
            NSLog(@"[INFO] --------------------- Session : %@", [self captureSession]);
            NSLog(@"[INFO] --------------------- Layer Session : %@", [self.prevLayer session]);
            
            [self.captureSession removeInput:self.videoInput];
            if( [[self captureSession] canAddInput:input]){
                [[self captureSession] addInput:input];
                [self setVideoInput:input];
            }else{
                [[self captureSession] addInput:[self videoInput]];
            }
            
//            [[self captureSession] commitConfiguration];
			break;
		};
	};
    
}

-(UIView*)square
{
	if (square == nil) {

		square = [[UIView alloc] initWithFrame:[self frame]];
		[self addSubview:square]; 

		self.stillImage = [[UIImageView alloc] init];
		self.stillImage.frame = [square bounds];
		[self addSubview:self.stillImage];

		if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {

            AVCaptureSession *session = [[AVCaptureSession alloc] init];
            
            [self setCaptureSession:session];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[INFO] --------------------- dispatch main is running");
                
                AVCaptureVideoPreviewLayer *previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
                
                self.prevLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.captureSession];
                self.prevLayer.frame = self.square.bounds;
                self.prevLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
                [self.square.layer addSublayer:self.prevLayer];
                
                self.captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
                
                if([self.captureDevice lockForConfiguration:nil]){
                    
                    if([self.captureDevice isFlashModeSupported:AVCaptureFlashModeOff]){
                        [self.captureDevice setFlashMode:AVCaptureFlashModeOff];
                        self.flashOn = NO;
                    };
                    
                    [self.captureDevice unlockForConfiguration];
                }
                
                
                NSError *errorDevice = nil;
                AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:[self captureDevice] error:&errorDevice];
                
                if( [session canAddInput:videoDeviceInput]){
                    [session addInput:videoDeviceInput];
                    [self setVideoInput:videoDeviceInput];
                }else{
                    NSLog(@"[ERROR] --------------------- Can't add the device : %@ to the session", [self captureDevice]);
                    NSLog(@"[ERROR] --------------------- Session %@", session);
                }
                
                
                
                // Set the default camera
                [self setCaptureDevice];
                
                NSError *error = nil;
                self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
                
                [self.stillImageOutput addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:AVCaptureStillImageIsCapturingStillImageContext];
                
                
                NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys: AVVideoCodecJPEG, AVVideoCodecKey, nil];
                [self.stillImageOutput setOutputSettings:outputSettings];
                
                [self.captureSession addOutput:self.stillImageOutput];
                
                
                [outputSettings release];
                
                // and off we go! ...
                [self.captureSession startRunning];
                
                
                NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
                                       @"started", @"state",
                                       nil];
                
                [self.proxy fireEvent:@"stateChange" withObject:event];
                
                // uh oh ... 
            bail:
                [self.captureSession release];
                if (error) {
                    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Failed with error %d", (int)[error code]]
                                                                        message:[error localizedDescription]
                                                                       delegate:nil 
                                                              cancelButtonTitle:@"oh dear" 
                                                              otherButtonTitles:nil];
                    [alertView show];
                    [alertView release];
                    [self teardownAVCapture];
                }
                
                
            }); // End of the block
            
            
            
          } else {
            // If camera is NOT avaialble
          	[self.proxy fireEvent:@"noCamera"];
          }        
        /////////////////////////////////////////////////////////////////////////////
        }

        return square;
      }



- (void)teardownAVCapture
{

    NSLog(@"[INFO] ---------------------  TEAR DOWN CAPTURE");

    [self.captureSession removeInput:self.videoInput];
//    [self.captureSession removeOutput:self.videoDataOutput];

    [self.captureSession stopRunning];
    
    NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"stopped", @"state",
                           nil];
    
    [self.proxy fireEvent:@"stateChange" withObject:event];

    [self.stillImageOutput removeObserver:self forKeyPath:@"capturingStillImage"];
    [self.stillImageOutput release];
    [self.prevLayer removeFromSuperlayer];
    [self.prevLayer release];
}

// perform a flash bulb animation using KVO to monitor the value of the capturingStillImage property of the AVCaptureStillImageOutput class
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( context == AVCaptureStillImageIsCapturingStillImageContext ) {
		BOOL isCapturingStillImage = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
		if ( isCapturingStillImage ) {
      // do flash bulb like animation
			flashView = [[UIView alloc] initWithFrame:[self.stillImage frame]];
			[flashView setBackgroundColor:[UIColor whiteColor]];
			[flashView setAlpha:0.f];

			[self addSubview:flashView];
      // fade it in            
			[UIView animateWithDuration:.3f
				animations:^{
					[flashView setAlpha:1.f];
				}
				];
		}
		else {
      // fade it out
			[UIView animateWithDuration:.3f
				animations:^{
					[flashView setAlpha:0.f];
				}
				completion:^(BOOL finished){
          // get rid of it
					[flashView removeFromSuperview];
					[flashView release];
					flashView = nil;
				}
				];
		}
	}
}

// utility routing used during image capture to set up capture orientation
- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
	AVCaptureVideoOrientation result = deviceOrientation;
	if ( deviceOrientation == UIDeviceOrientationLandscapeLeft )
		result = AVCaptureVideoOrientationLandscapeRight;
	else if ( deviceOrientation == UIDeviceOrientationLandscapeRight )
		result = AVCaptureVideoOrientationLandscapeLeft;
	return result;
}

@end
