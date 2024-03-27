# waveIMG
Code and example data for identifying breaking waves in surfzone video/imagery. 

There are two stages:
- Create Training Data & Train Network:
  -- in the `/mfiles/` directory is a matlab application `select_CNN_training_data.mlapp`
  -- use this function to load images and annotate breaking wave features
  -- these are saved as image/label pairs for training a convolutional neural network (CNN), called `imgNet`.
  -- the `video_processing` directory has CIRN processing scripts and code written by Ciara Dooley and Levi Gorrell
  -- lastly, create and train the network using `make_IMG_CNN_fullImage.m`
- Implement *imgNet* to identify breaking waves:
  -- in the `/mfiles/wave_front_detection/` directory is the script `main_workflow.m` that has all the necessary steps
  -- the steps are:
     1) define camera, grid, network parameters
     2) load a video, read frames, rectify and interp to regular FRF grid
     3) (optional: 1=yes/0=no) re-scale the image intensity (gray-scale) to enhance contrast between foam/water
     4) apply neural network to get an array of front probabilities (continuous 0=non-front to 1=front)
     5) extract the coordinates of the ridges/maxima in (4). This is the sketchy/subjective/kludgy. 


## How to use program:
- Make sure you are in the mfiles directory when you run it
- Put the files you need in the data folder if you want it to auto load the files in the app
   - if not then select the folder that the files are in when you hit the select video files button
- When selecting fronts, zoom in before clicking the select fronts button no ensure the best accuracy when tracing the pixels in the image.
- Do not spam click save & continue, if you have already done so once. Once it saves and continues, you must either load new frame, or go to another file and start selecting fronts there.
- If you try to plot frames and get an error, the frames you are trying to plot may be more than there actually are in the video. Try plotting a fewer number of frames.






## To Do:
create a new matlab-app for training data:
   1) figure/axes properties:
      - [x] make application window open to full screen. 
    ```drawnow; app.UIFigure.WindowState = 'maximized';```
      - [ ] make the plot axes look nice.
   3) get list of video-files (*i.e.*, path & filename; was `import_rod13.m`):
      - [x] prompt user to highlight directories where the vidoe files are located
      - [x] current directory drop-down selector for multiple video sub-directories
      - [x] need call-back to update filenames when user selects a different sub-dir; anything else? 
      - [x] current filename drop-down selector for multiple videos in each sub-directory
      - [ ] \(do this later) will likely need call-backs to re-initialize video loading and rectification.
   4) load and rectify image frames from the selected movie (.avi or .mp4; was `rectify_vd.m`):
      - [x] extract relevant variables/values from `getCameraParams.m` and `getOCMparams.m`
      - [ ] \(do this later) add an option for user to point to manually input values, direct to a .mat file with values.
      - [x] read in a video frame
      - [ ] get the time string from the video file or the time file to get "z_tide"
      - [x] rectify the frame to user defined (x,y) grid,
            - editable fields for min/max of (x,y), and spacing (dx,dy)
	    - make default values the same as those used in `rectify_vd.m`
      - [x] display frames
            - define axes properties,
	    - display using imagesc(x,y,frame)
	    - use a for-loop to show several frames (maybe 10) and make it like a movie using the `pause.m` command
            - stop on final image and prompt user to select breaking regions
   5) select points bounding the breaking wave fronts
      - [x] use function like `drawfreehand.m` to select points using mouse
      - [x] keep a log with: video filename, the app.info video/grid parameters, frame number, and front pixel row/column,
	    - add call-back for the "save & continue" button
            - check that you can save multiple ROIs for a single frame
            - select multiple ROIs, click save, on a new frame select more ROIs and save. Does it work?
            - make sure it works when there is or isn't an existing "WaveImageSpecs.mat" file.
      - [x] use these points to create a training label image where:
            - the size [rows,columns]=[ny,nx] of the label matches the rectified image
	    - the label is class uint8() and has values:
	      - 0 in the black bordering region outside the actual image
	      - 127 for non-breaking wave regions (beach, water, or trailing foam)
	      - 255 for points/regions selected by user
   6) archive training image/label pairs
      - [x] the images should be in a subdirectory called `trainingImages/`; labels should be in `trainingLabels/`
      - [x] also keep a running log of the input image path, the frame number, and pixels used to make training labels
      - [x] use video filename and frame number in the app.log structure to create image/label filename; e.g., see startupFcn for "cwd",
        ```
        videoPath   = app.log(app.logNum).videoFile;
        splitPath   = split(videoPath, [filesep]);
        imageName = [cwd,filesep,'..', filesep,'trainingData',filesep,'trainingImages',filesep,splitPath{end}(1:end-4), '_Frame_', num2string( app.log(app.logNum).frameIndex), '.png' ];
        app.log(app.logNum).imageName = imageName;
        imwrite(app.IMG,imageName);
        ```
        and so similarly for a ```labelName``` variable.     
## Train the network and sell to google!

