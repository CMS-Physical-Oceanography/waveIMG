%
% get a structure with training data
trainDataPath = '/home/derek/projects/ShortCrests/IMG/data/trainingFullImages/';
imageDir      = [trainDataPath, 'trainingImages/'];
labelDir      = [trainDataPath, 'trainingLabels/'];
%
%             background, nonFront, front
classNames = ["bckgrnd" , "nonFront" ,  "front"];
classLabel = [0         ,  127    ,  255];
pxds       = pixelLabelDatastore(labelDir,classNames,classLabel);
imds       = imageDatastore(imageDir);
%
%
%
TrainingData  = combine(imds,pxds);
%
numFiles = length(imds.Files);
Ntrain   = floor(0.75*numFiles);
perm     = randperm(numFiles);
imdsValid  = subset(TrainingData,perm(Ntrain+1:numFiles));
imdsTrain  = subset(TrainingData,perm(1:Ntrain));
%
%
% get input layer size
img = readimage(imds,perm(10));
lbl = readimage(pxds,perm(10));
[Ny,Nx,Nt] = size(img);
%
% determine the ratios of pixel classes
frac   = [0 0 0];
for ii = 1:numFiles
    lbl   = readimage(pxds,perm(ii));
    [~,class] = ismember(lbl,{'bckgrnd','nonFront','front'});
    Nbg   = numel(find(class==1));    
    Nnf   = numel(find(class==2));    
    Nn    = numel(find(class==3));    
    frac  = frac + [Nbg Nnf Nn]./(Ny*Nx);
end
unitGain = 1./frac(2);
weights = 1./frac./unitGain
%
%
numFilters = 16;
filterSize = 5;
numClasses = 3;
layers = [
    imageInputLayer([Ny Nx Nt])
    convolution2dLayer(filterSize,numFilters,'Padding','same')
    batchNormalizationLayer
    reluLayer()
    maxPooling2dLayer(3,'Stride',2,'Padding',[1 1])
    convolution2dLayer(filterSize,numFilters,'Padding','same')
    batchNormalizationLayer    
    reluLayer()
    transposedConv2dLayer(4,numFilters,'Stride',2,'Cropping','same');
    convolution2dLayer(1,numClasses,'Padding','same');
    batchNormalizationLayer
    softmaxLayer()
    pixelClassificationLayer('Classes',classNames,'ClassWeights',[1 1 20])
    ];
%
%
%
options = trainingOptions('sgdm',...
                          'InitialLearnRate',0.005,...'MaxEpocs', 4,...
                          'Shuffle','every-epoch',...
                          'ValidationFrequency',5,...
                          'Verbose',0,...
                          'ValidationData',imdsValid,...                          
                          'ExecutionEnvironment','parallel',...                          
                          'Plots','training-progress');
%
imgNet = trainNetwork(imdsTrain,layers,options);
%
% visually evaluate skill
% get input layer size
imIn = '/data0/ShortCrests/IMG/data/trainingFullImages/trainingImages/image_1014_1315_0392.png'
[~,imNum]= ismember(imIn,imds.Files);
img = readimage(imds,perm(imNum));
lbl = readimage(pxds,perm(imNum));
lbl0 = semanticseg(img,imgNet);
act  = activations(imgNet,img,'softmax');
A = labeloverlay(img,lbl);
B = labeloverlay(img,lbl0);
figure,
subplot(1,2,1)
imshow(A)
title('Pixel Network')
subplot(1,2,2)
imshow(B)
hold on, contour(act(:,:,3),[0.85 0.85],'r')
title('Image Network')
%
%
save('../mat_data/imgNet_v8.mat','imgNet')